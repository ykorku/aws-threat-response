# Automated EC2 threat detection and response on AWS

A small but realistic incident-response pipeline: Amazon GuardDuty detects
a threat against an EC2 instance, EventBridge routes the finding to a
Lambda function, and the function takes forensic snapshots, isolates the
instance into a no-network security group, tags it with incident
metadata, and alerts a human over SNS — all without anyone touching the
console.

This is not a toy "Lambda fires when GuardDuty fires" demo. The function
makes deliberate decisions: it preserves evidence before changing
anything, it respects a manual override tag so a human can opt an
instance out of automation, and it fails gracefully when GuardDuty
references an instance that doesn't exist (which happens during testing
with sample findings).

## Architecture

```
EC2 instance (compromised)
        |
        v
   GuardDuty  -- detects the threat
        |
        v
  EventBridge -- routes the finding
        |
        v
     Lambda   -- snapshots volumes, isolates instance, tags it
        |
        +----------------> SNS        (emails you)
        |
        +----------------> CloudTrail (every API call is logged)
```

Everything is provisioned with Terraform — no manual console clicking.
That matters more than it sounds: anyone can click buttons in the AWS
console, but writing infrastructure as code is what's actually expected
of you on the job, and it's what makes this reproducible and reviewable.

## Prerequisites

- An AWS account where you're comfortable creating a handful of billable
  resources (see **Cost** below — this is cheap but not free)
- AWS CLI configured with credentials that have permission to create
  VPCs, EC2 instances, GuardDuty detectors, CloudTrail, Lambda, IAM
  roles, SNS topics, and EventBridge rules
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- Python 3.12 available locally is not required — Terraform packages
  the Lambda code for you

## Deploying

1. Copy the example variables file and fill in your email address:

   ```
   cp terraform.tfvars.example terraform.tfvars
   ```

   Edit `terraform.tfvars` and set `alert_email` to an address you can
   check during testing.

2. Initialize and apply:

   ```
   terraform init
   terraform plan
   terraform apply
   ```

3. **Confirm the SNS subscription.** Within a minute of applying, you'll
   get an email from AWS asking you to confirm the subscription. Click
   the link — if you skip this step, you will never receive alerts and
   will spend ten confused minutes wondering why.

4. Note the outputs, especially `test_instance_id` and
   `guardduty_detector_id` — you'll need them for testing.

## Testing — two methods

GuardDuty sample findings use placeholder instance IDs that don't exist
in your account, which is realistic (you want your function to handle
"finding references a resource I can't find" without crashing) but
doesn't exercise the actual isolate/snapshot logic. So test both ways.

### Method 1: sample finding (verifies the wiring)

```
aws guardduty create-sample-findings \
  --detector-id <guardduty_detector_id> \
  --finding-types UnauthorizedAccess:EC2/SSHBruteForce
```

Within a minute or two you should get an SNS email saying the instance
referenced in the finding "could not be found in this account." That's
the correct, expected outcome — it confirms GuardDuty, EventBridge, and
Lambda are all correctly wired together end to end.

### Method 2: manual invocation against your real test instance (verifies the remediation)

This is the test that actually proves the isolate-and-snapshot logic
works, and it's the one worth recording a screen capture of for your
portfolio.

1. Open `test/sample_finding_event.json` and replace
   `REPLACE_WITH_YOUR_TEST_INSTANCE_ID` with the `test_instance_id`
   output value.

2. Invoke the Lambda directly with that event:

   ```
   aws lambda invoke \
     --function-name <lambda_function_name> \
     --payload file://test/sample_finding_event.json \
     --cli-binary-format raw-in-base64-out \
     response.json
   ```

3. Check `response.json` — you should see `"status": "isolated"` and a
   list of snapshot IDs.

4. Verify in the console or CLI: the instance's security group should
   now be the quarantine group, there should be a new EBS snapshot
   tagged `Purpose=forensic-auto-isolation`, and the instance should have
   the `IncidentStatus=isolated` tag. You should also get a second SNS
   email with the real isolation summary.

5. Optional but worth doing once: tag the test instance with
   `do-not-auto-remediate=true`, re-run the invocation, and confirm the
   function skips isolation and just notifies you. This is the detail
   that shows you thought about false positives, not just the happy path.

## Cost

GuardDuty has a 30-day free trial per account, after which it's billed
per analyzed event (a few dollars a month for a single test instance).
CloudTrail's management-event trail is free; the S3 bucket storing logs
costs fractions of a cent at this scale. The `t3.micro` test instance is
free-tier eligible in most accounts. Run `terraform destroy` when you're
done to avoid any ongoing charges.

```
terraform destroy
```

## Threat model — what this defends against, and what it doesn't

This pipeline detects and responds to GuardDuty's EC2-related finding
types: things like a compromised instance scanning for SSH brute-force
targets, communicating with a known command-and-control endpoint, or
exhibiting cryptocurrency-mining behavior. It does not detect threats
GuardDuty itself doesn't cover (it relies entirely on GuardDuty's
detection — there's no custom detection logic here), and it doesn't
protect against an attacker who has already obtained IAM credentials
with permission to modify security groups or disable GuardDuty, since
at that point they could simply reverse the isolation.

## Tradeoffs and what I'd change for production

Automated remediation always trades speed for risk of false-positive
disruption. A few decisions worth being able to defend in an interview:

**Why isolate instead of terminate?** Termination destroys evidence.
Isolating into a no-network security group stops the bleeding (no more
outbound C2 traffic, no more lateral movement) while preserving the
instance and its volumes for investigation.

**Why a tag-based override instead of always auto-remediating?**
Production environments have instances where an automatic network cutoff
would be worse than the threat — a database primary, for example. The
`do-not-auto-remediate` tag gives operators an escape hatch without
disabling the whole pipeline.

**What I'd add for a real production deployment:** a human-approval step
for lower-severity findings (auto-remediate only above a severity
threshold, page someone for the rest), multi-account aggregation via
GuardDuty's delegated administrator feature instead of a single-account
detector, and a dead-letter queue on the EventBridge target so a failed
Lambda invocation doesn't just silently disappear.

## Possible extensions

- Add a severity threshold so only high-severity findings trigger
  automatic isolation; lower-severity ones just notify.
- Extend the Lambda to also revoke any IAM credentials associated with
  the instance's role, in case the compromise involves stolen temporary
  credentials.
- Pair this with network-layer detection (e.g., a Suricata sensor on the
  VPC) to compare cloud-control-plane detection against network-level
  detection of the same attack.
