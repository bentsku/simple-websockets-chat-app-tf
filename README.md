# simple-websockets-chat-app-tf

Quick sample for https://github.com/localstack/localstack/issues/9002
Based on https://github.com/aws-samples/simple-websockets-chat-app

### How to run

Start LocalStack with your preferred way.

Once LocalStack is started, you can then create the S3 bucket containing the Lambda code.

```bash
# navigate to the lambda folder
$ cd lambda
# create the `snapshot` bucket
$ awslocal s3 mb s3://snapshot
# sync the different directories to create the code archives for lambda as defined in main.tf
$ awslocal s3 sync . s3://snapshot
```

You can then deploy the infrastructure with Terraform using `tflocal`. 

```bash
$ tflocal init
$ tflocal apply --auto-approve
```

Now the infrastructure is deployed, you can test it using `wscat`

```bash
$ wscat -c ws://localhost:4510
Connected (press CTRL+C to quit)
> {"message":"hello", "header": "111", "id": "111", "data": "test"}
< test
< Data sent.
> {"action":"sendmessage", "data":"hello world"}
< hello world
< Data sent.
```
