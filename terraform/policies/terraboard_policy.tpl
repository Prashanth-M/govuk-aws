{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
             ],
            "Resource": [
                "arn:aws:s3:::govuk-terraform-state-${aws_environment}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject"
             ],
            "Resource": [
                "arn:aws:s3:::govuk-terraform-state-${aws_environment}/*"
            ]
        }
    ]
 }
