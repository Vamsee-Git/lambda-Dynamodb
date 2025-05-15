# Use the AWS Lambda Python base image
FROM public.ecr.aws/lambda/python:3.9

# Set the working directory
WORKDIR /var/task

# Copy the application code
COPY app.py ${LAMBDA_TASK_ROOT} 

# Set the handler function
CMD ["app.lambda_handler"]