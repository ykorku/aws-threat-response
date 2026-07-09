"""
isolate_instance.py

Triggered by an EventBridge rule whenever GuardDuty publishes a finding.

If the finding references an EC2 instance, this function:
  1. Looks up the instance and checks for a manual override tag.
  2. Creates forensic EBS snapshots of its attached volumes.
  3. Swaps its security groups for a no-ingress/no-egress quarantine group.
  4. Tags the instance with incident metadata for later investigation.
  5. Publishes a summary of what happened to SNS.

The instance is never terminated. Isolating (not destroying) preserves
it for forensics — you can still attach a forensics workstation to the
snapshots or inspect the instance via Session Manager if needed.

Required environment variables:
  QUARANTINE_SG_ID  - security group ID with no inbound/outbound rules
  SNS_TOPIC_ARN     - SNS topic to publish incident notifications to

Tag-based override:
  An instance tagged "do-not-auto-remediate=true" will never be isolated
  automatically. The function still notifies you so a human can decide.
"""

import os
import datetime
import boto3
from botocore.exceptions import ClientError

ec2 = boto3.client("ec2")
sns = boto3.client("sns")

QUARANTINE_SG_ID = os.environ["QUARANTINE_SG_ID"]
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
SKIP_TAG_KEY = "do-not-auto-remediate"


def lambda_handler(event, context):
    detail = event.get("detail", {})
    finding_type = detail.get("type", "Unknown")
    severity = detail.get("severity", 0)
    finding_id = detail.get("id", "unknown")

    instance_id = _extract_instance_id(detail)
    if not instance_id:
        _notify(
            f"GuardDuty finding {finding_id} ({finding_type}) did not reference an "
            f"EC2 instance. No remediation action was taken."
        )
        return {"status": "no_instance_in_finding"}

    try:
        instance = _get_instance(instance_id)
    except ClientError:
        # Expected when testing with `aws guardduty create-sample-findings`,
        # which uses placeholder instance IDs that don't exist in your account.
        _notify(
            f"GuardDuty finding {finding_id} ({finding_type}) referenced instance "
            f"{instance_id}, which could not be found in this account. This is "
            f"expected when testing with GuardDuty sample findings."
        )
        return {"status": "instance_not_found", "instance_id": instance_id}

    if _has_skip_tag(instance):
        _notify(
            f"GuardDuty finding {finding_id} ({finding_type}, severity {severity}) "
            f"flagged instance {instance_id}, but it is tagged "
            f"'{SKIP_TAG_KEY}=true'. Skipping automated isolation — manual "
            f"review required."
        )
        return {"status": "skipped_protected_instance", "instance_id": instance_id}

    snapshot_ids = _snapshot_volumes(instance)
    _isolate(instance_id)
    _tag_instance(instance_id, finding_id, finding_type)

    _notify(
        f"Isolated instance {instance_id} in response to GuardDuty finding "
        f"{finding_id} ({finding_type}, severity {severity}). Created "
        f"{len(snapshot_ids)} forensic snapshot(s): "
        f"{', '.join(snapshot_ids) if snapshot_ids else 'none'}. Security "
        f"groups replaced with quarantine group {QUARANTINE_SG_ID}."
    )

    return {"status": "isolated", "instance_id": instance_id, "snapshots": snapshot_ids}


def _extract_instance_id(detail):
    try:
        return detail["resource"]["instanceDetails"]["instanceId"]
    except KeyError:
        return None


def _get_instance(instance_id):
    response = ec2.describe_instances(InstanceIds=[instance_id])
    return response["Reservations"][0]["Instances"][0]


def _has_skip_tag(instance):
    for tag in instance.get("Tags", []):
        if tag["Key"] == SKIP_TAG_KEY and tag["Value"].lower() == "true":
            return True
    return False


def _snapshot_volumes(instance):
    instance_id = instance["InstanceId"]
    timestamp = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    snapshot_ids = []

    for mapping in instance.get("BlockDeviceMappings", []):
        ebs = mapping.get("Ebs")
        if not ebs:
            continue
        snapshot = ec2.create_snapshot(
            VolumeId=ebs["VolumeId"],
            Description=(
                f"Forensic snapshot of {ebs['VolumeId']} from {instance_id}, "
                f"auto-created {timestamp}"
            ),
            TagSpecifications=[
                {
                    "ResourceType": "snapshot",
                    "Tags": [
                        {"Key": "Purpose", "Value": "forensic-auto-isolation"},
                        {"Key": "SourceInstance", "Value": instance_id},
                    ],
                }
            ],
        )
        snapshot_ids.append(snapshot["SnapshotId"])

    return snapshot_ids


def _isolate(instance_id):
    ec2.modify_instance_attribute(InstanceId=instance_id, Groups=[QUARANTINE_SG_ID])


def _tag_instance(instance_id, finding_id, finding_type):
    ec2.create_tags(
        Resources=[instance_id],
        Tags=[
            {"Key": "IncidentStatus", "Value": "isolated"},
            {"Key": "GuardDutyFindingId", "Value": finding_id},
            {"Key": "GuardDutyFindingType", "Value": finding_type},
            {"Key": "IsolatedAt", "Value": datetime.datetime.utcnow().isoformat()},
        ],
    )


def _notify(message):
    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject="AWS auto-remediation: EC2 instance isolated",
        Message=message,
    )
