import * as cdk from 'aws-cdk-lib';
import { GpuHostStack } from '../lib/gpu-host-stack';

const account = process.env.CDK_DEFAULT_ACCOUNT;
if (!account) {
  throw new Error('Set an AWS profile before synthesizing this stack.');
}

const app = new cdk.App();
new GpuHostStack(app, 'GpuHostStack', {
  env: { account, region: 'us-east-1' },
  terminationProtection: true,
});
