#!/bin/bash

# This script will delete root access from all accounts in the specified OUs
# Create an ou_list.txt file and specify the OUs you want to process
# This script assumes you have setup Root access management and have credentials setup on your machine
# https://docs.aws.amazon.com/IAM/latest/UserGuide/id_root-enable-root-access.html

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install jq to parse JSON."
    exit 1
fi

# Store original credentials
ORIGINAL_AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
ORIGINAL_AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
ORIGINAL_AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN

# Read OUs from file and process each one
while IFS= read -r OU_ID || [[ -n "$OU_ID" ]]; do
    # Skip empty lines and comments
    [[ -z "$OU_ID" || "$OU_ID" =~ ^[[:space:]]*# ]] && continue
    
    echo "Processing OU: $OU_ID"
    
    # Get the list of AWS account IDs in the OU
    aws organizations list-accounts-for-parent --parent-id "$OU_ID" > accounts.json
    
    if [ ! -f "accounts.json" ] || [ "$(jq -r '.Accounts' accounts.json 2>/dev/null)" == "null" ]; then
        echo "Error: Failed to get accounts for OU $OU_ID"
        continue
    fi

    # Loop through the list of account IDs and delete root
    for account in $(jq -r '.Accounts[].Id' accounts.json); do
        echo "Processing account: $account in OU: $OU_ID"
        
        # Restore original credentials before assuming root
        export AWS_ACCESS_KEY_ID=$ORIGINAL_AWS_ACCESS_KEY_ID
        export AWS_SECRET_ACCESS_KEY=$ORIGINAL_AWS_SECRET_ACCESS_KEY
        export AWS_SESSION_TOKEN=$ORIGINAL_AWS_SESSION_TOKEN
        
        # Assume root in the target account
        aws sts assume-root \
            --target-principal "$account" \
            --task-policy-arn arn=arn:aws:iam::aws:policy/root-task/IAMDeleteRootUserCredentials > credentials.json

        # Check if credentials.json file exists and contains valid data
        if [ ! -f "credentials.json" ] || [ "$(jq -r '.Credentials.AccessKeyId' credentials.json 2>/dev/null)" == "null" ]; then
            echo "Error: Failed to assume root for account $account"
            continue
        fi

        # Export the temporary credentials
        export AWS_ACCESS_KEY_ID=$(jq -r '.Credentials.AccessKeyId' credentials.json)
        export AWS_SECRET_ACCESS_KEY=$(jq -r '.Credentials.SecretAccessKey' credentials.json)
        export AWS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken' credentials.json)

        # Verify credentials work
        if ! aws sts get-caller-identity &>/dev/null; then
            echo "Error: Failed to validate credentials for account $account"
            continue
        fi

        echo "Successfully assumed root in account $account"

        # Delete root user credentials
        echo "Deleting root user credentials for account $account"
        aws iam delete-login-profile
        
        # Delete access key
        aws iam delete-access-key

        # Delete signing certificate
        aws iam delete-signing-certificate

        # Delete MFA devices
        echo "Deleting MFA devices for account $account"
        for serial_number in $(aws iam list-mfa-devices --query "MFADevices[].SerialNumber" --output text); do
            echo "Deactivating MFA device: $serial_number"
            aws iam deactivate-mfa-device --serial-number "$serial_number"
            echo "Deleting MFA device: $serial_number"
            aws iam delete-virtual-mfa-device --serial-number "$serial_number"
        done

        # Clean up credentials file
        rm -f credentials.json
        
        echo "Completed processing account: $account"
        echo "----------------------------------------"
    done
    
    # Clean up accounts file for this OU
    rm -f accounts.json
    echo "Completed processing OU: $OU_ID"
    echo "========================================"

    export AWS_ACCESS_KEY_ID=$ORIGINAL_AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY=$ORIGINAL_AWS_SECRET_ACCESS_KEY
    export AWS_SESSION_TOKEN=$ORIGINAL_AWS_SESSION_TOKEN

done < "ou_list.txt"

