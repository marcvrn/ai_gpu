import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { Construct } from 'constructs';

export class GpuHostStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: cdk.StackProps) {
    super(scope, id, props);

    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVpc', { isDefault: true });
    const securityGroup = new ec2.SecurityGroup(this, 'GpuSecurityGroup', {
      vpc,
      allowAllOutbound: true,
      description: 'Outbound access for SSM and model downloads; no inbound access',
    });

    const role = new iam.Role(this, 'GpuRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    const setupScript = fs.readFileSync(path.join(__dirname, '../../scripts/install-wan.sh'), 'utf8');
    const userData = ec2.UserData.custom([
      '#!/bin/bash',
      'set -Eeuo pipefail',
      "cat >/usr/local/sbin/ai-deploy-setup <<'AI_DEPLOY_SETUP'",
      setupScript,
      'AI_DEPLOY_SETUP',
      'chmod 700 /usr/local/sbin/ai-deploy-setup',
      '/usr/local/sbin/ai-deploy-setup',
    ].join('\n'));

    const instanceProfile = new iam.CfnInstanceProfile(this, 'GpuInstanceProfile', {
      roles: [role.roleName],
    });

    // An omitted subnet lets EC2 choose an available default subnet in this region.
    const instance = new ec2.CfnInstance(this, 'GpuInstance', {
      imageId: 'ami-024b2999242b4b38d',
      instanceType: 'g6e.xlarge',
      iamInstanceProfile: instanceProfile.ref,
      securityGroupIds: [securityGroup.securityGroupId],
      blockDeviceMappings: [{
        deviceName: '/dev/sda1',
        ebs: { encrypted: true, volumeSize: 80, volumeType: 'gp3' },
      }],
      metadataOptions: { httpTokens: 'required' },
      userData: cdk.Fn.base64(userData.render()),
    });

    cdk.Tags.of(this).add('Project', 'ai_deploy');
    cdk.Tags.of(this).add('ManagedBy', 'aws-cdk');

    new cdk.CfnOutput(this, 'InstanceId', { value: instance.ref });
  }
}
