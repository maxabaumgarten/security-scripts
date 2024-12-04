# security-scripts
A collection of security scripts that are useful

## AWS Scripts

- [Root Access Management](aws/Root_Access_Management/main.sh)
  - This script will delete root access from all accounts in the specified OUs using [Root access management from AWS](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_root-enable-root-access.html)
  - Why was this not written in python?
    - The Assume-Root API was being wonky in boto3.

