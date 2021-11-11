PROJECT_NAME := spring-boot-$(shell date '+%s')
CODE_BUILD_CACHE_BUCKET := 1632566015-code-build-cache
#CODEDEPLOY_METHOD := CodeDeployDefault.OneAtATime
CODEDEPLOY_METHOD := CodeDeployDefault.HalfAtATime
#CODEDEPLOY_METHOD := CodeDeployDefault.AllAtOnce

init:
	@echo $(PROJECT_NAME) > .projectname

build: prepare_build launch_build

deploy: deploy_resources deploy_sw

prepare_build:
	@PROJECT_NAME=$(shell cat .projectname) && \
	cd infrastructure && \
	(aws cloudformation deploy \
		--capabilities CAPABILITY_IAM \
		--template-file codebuild/_cf-codebuild.yml \
		--stack-name $${PROJECT_NAME}-build \
		--parameter-overrides \
			ProjectName=$${PROJECT_NAME} \
			ArtifactBucketName=$${PROJECT_NAME} \
			CacheBucket=$(CODE_BUILD_CACHE_BUCKET) > /dev/null & ) && \
	./dump/cf_events.sh $${PROJECT_NAME}-build

launch_build:
	@PROJECT_NAME=$(shell cat .projectname) && \
	BUILD_ID=$$(aws codebuild start-build --project-name $${PROJECT_NAME} \
		--buildspec-override infrastructure/codebuild/buildspec.yml \
		--query "build.id" --output text) && \
	echo Triggered build $${BUILD_ID} && \
	SPLIT_BUILD_ID=($${BUILD_ID//:/ }) && \
	echo Launching build instance... && sleep 5 && \
	aws logs tail /aws/codebuild/$${PROJECT_NAME} --follow --log-stream-name-prefix "$${SPLIT_BUILD_ID[1]}"

deploy_sw:
	@PROJECT_NAME=$(shell cat .projectname) && \
	make deploy_resources && \
	DEPLOYMENT_ID=$$(aws deploy create-deployment \
		--deployment-group-name $${PROJECT_NAME} \
		--application-name $${PROJECT_NAME} \
		--s3-location bucket=$${PROJECT_NAME},key=$${PROJECT_NAME}/build-output.zip,bundleType=zip \
		--deployment-config-name $(CODEDEPLOY_METHOD) \
		--query "deploymentId" --output text) && \
	echo DEPLOYMENT_ID $${DEPLOYMENT_ID} && \
	sleep 2 && \
	./infrastructure/dump/codedeploy_events.sh $${DEPLOYMENT_ID}

deploy_resources:
	@PROJECT_NAME=$(shell cat .projectname) && \
	cd infrastructure && \
	(aws cloudformation deploy \
		--capabilities CAPABILITY_IAM \
		--template-file codedeploy/_cf-codedeploy.yml \
		--stack-name $${PROJECT_NAME}-deploy \
		--parameter-overrides \
			ProjectName=$${PROJECT_NAME} > /dev/null & ) && \
	./dump/cf_events.sh $${PROJECT_NAME}-deploy

endpoint:
	@PROJECT_NAME=$(shell cat .projectname) && \
	ALB_DNS=$$(aws cloudformation describe-stacks --stack-name $${PROJECT_NAME}-deploy --query "Stacks[0].Outputs[0].OutputValue" --output text) && \
	echo ALB_DNS = $${ALB_DNS}

destroy:
	@PROJECT_NAME=$(shell cat .projectname) && \
	aws s3 rm s3://$${PROJECT_NAME} --recursive && \
	aws cloudformation delete-stack --stack-name $${PROJECT_NAME}-build && \
	aws cloudformation delete-stack --stack-name $${PROJECT_NAME}-deploy && \
	rm .projectname
