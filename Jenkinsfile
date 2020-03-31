/*
 * This is a vanilla Jenkins pipeline that relies on the Jenkins kubernetes plugin to dynamically provision agents for
 * the build containers.
 *
 * The individual containers are defined in the `jenkins-pod-template.yaml` and the containers are referenced by name
 * in the `container()` blocks. The underlying pod definition expects certain kube Secrets and ConfigMap objects to
 * have been created in order for the Pod to run. See `jenkins-pod-template.yaml` for more information.
 *
 * The cloudName variable is set dynamically based on the existance/value of env.CLOUD_NAME which allows this pipeline
 * to run in both Kubernetes and OpenShift environments.
 */

def buildAgentName(String jobNameWithNamespace, String buildNumber, String namespace) {
    def jobName = removeNamespaceFromJobName(jobNameWithNamespace, namespace);

    if (jobName.length() > 52) {
        jobName = jobName.substring(0, 52);
    }

    return "a.${jobName}${buildNumber}".replace('_', '-').replace('/', '-').replace('-.', '.');
}

def removeNamespaceFromJobName(String jobName, String namespace) {
    return jobName.replaceAll(namespace + "-", "").replaceAll(jobName + "/", "");
}

def buildSecretName(String jobNameWithNamespace, String namespace) {
    return jobNameWithNamespace.replaceFirst(namespace + "/", "").replaceFirst(namespace + "-", "").replace(".", "-").toLowerCase();
}

def secretName = buildSecretName(env.JOB_NAME, env.NAMESPACE)
println "Job name: ${env.JOB_NAME}"
println "Secret name: ${secretName}"

def buildLabel = buildAgentName(env.JOB_NAME, env.BUILD_NUMBER, env.NAMESPACE);
def branch = env.BRANCH ?: "master"
def namespace = env.NAMESPACE ?: "dev"
def cloudName = env.CLOUD_NAME == "openshift" ? "openshift" : "kubernetes"
def workingDir = "/home/jenkins/agent"
podTemplate(
   label: buildLabel,
   cloud: cloudName,
   yaml: """
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins
  volumes:
    - emptyDir: {}
      name: varlibcontainers
  containers:
    - name: jdk11
      image: maven:3.6.3-jdk-11-slim
      tty: true
      command: ["/bin/bash"]
      workingDir: ${workingDir}
      envFrom:
        - configMapRef:
            name: pactbroker-config
            optional: true
        - configMapRef:
            name: sonarqube-config
            optional: true
        - secretRef:
            name: sonarqube-access
            optional: true
      env:
        - name: HOME
          value: ${workingDir}
        - name: SONAR_USER_HOME
          value: ${workingDir}
    - name: node
      image: node:12-stretch
      tty: true
      command: ["/bin/bash"]
      workingDir: ${workingDir}
      envFrom:
        - configMapRef:
            name: pactbroker-config
            optional: true
        - configMapRef:
            name: sonarqube-config
            optional: true
        - secretRef:
            name: sonarqube-access
            optional: true
      env:
        - name: HOME
          value: ${workingDir}
        - name: BRANCH
          value: ${branch}
        - name: GIT_AUTH_USER
          valueFrom:
            secretKeyRef:
              name: ${secretName}
              key: username
        - name: GIT_AUTH_PWD
          valueFrom:
            secretKeyRef:
              name: ${secretName}
              key: password
    - name: ibmcloud
      image: docker.io/garagecatalyst/ibmcloud-dev:1.0.10
      tty: true
      command: ["/bin/bash"]
      workingDir: ${workingDir}
      envFrom:
        - configMapRef:
            name: ibmcloud-config
        - secretRef:
            name: ibmcloud-apikey
        - configMapRef:
            name: artifactory-config
            optional: true
        - secretRef:
            name: artifactory-access
            optional: true
      env:
        - name: CHART_NAME
          value: base
        - name: CHART_ROOT
          value: chart
        - name: TMP_DIR
          value: .tmp
        - name: HOME
          value: /home/devops
        - name: ENVIRONMENT_NAME
          value: ${namespace}
        - name: BUILD_NUMBER
          value: ${env.BUILD_NUMBER}
"""
) {
    node(buildLabel) {
        container(name: 'jdk11', shell: '/bin/bash') {
            checkout scm
            stage('Build') {
                sh '''
                    ./mvnw package
                '''
            }
            stage('Test') {
                sh '''#!/bin/bash
                    ./mvnw test
                '''
            }
        }
        container(name: 'node', shell: '/bin/bash') {
            stage('Tag release') {
                sh '''#!/bin/bash
                    set -x
                    set -e

                    git fetch origin ${BRANCH} --tags
                    git checkout ${BRANCH}
                    git branch --set-upstream-to=origin/${BRANCH} ${BRANCH}

                    git config --global user.name "Jenkins Pipeline"
                    git config --global user.email "jenkins@ibmcloud.com"
                    git config --local credential.helper "!f() { echo username=\\$GIT_AUTH_USER; echo password=\\$GIT_AUTH_PWD; }; f"

                    mkdir -p ~/.npm
                    npm config set prefix ~/.npm
                    export PATH=$PATH:~/.npm/bin
                    npm i -g release-it

                    if [[ "${BRANCH}" != "master" ]]; then
                        PRE_RELEASE="--preRelease=${BRANCH}"
                    fi

                    release-it patch ${PRE_RELEASE} \
                      --ci \
                      --no-npm \
                      --no-git.requireCleanWorkingDir \
                      --verbose \
                      -VV

                    echo "IMAGE_VERSION=$(git describe --abbrev=0 --tags)" > ./env-config
                    echo "IMAGE_NAME=$(basename -s .git `git config --get remote.origin.url` | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')" >> ./env-config

                    cat ./env-config
                '''
            }
        }
        container(name: 'ibmcloud', shell: '/bin/bash') {
            stage('Build image') {
                sh '''#!/bin/bash
                    . ./env-config
                    ibmcloud login -u $REGISTRY_USER -p $APIKEY
                    echo -e "=========================================================================================="
                    echo -e "BUILDING CONTAINER IMAGE: ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_VERSION}"
                    set -x
                    ibmcloud cr build -t ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_VERSION} .
                    if [[ $? -ne 0 ]]; then
                      exit 1
                    fi

                    if [[ -n "${BUILD_NUMBER}" ]]; then
                        echo -e "BUILDING CONTAINER IMAGE: ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_VERSION}-${BUILD_NUMBER}"
                        ibmcloud cr image-tag ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_VERSION} ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_VERSION}-${BUILD_NUMBER}
                    fi
                '''
            }
            stage('Deploy to DEV env') {
                sh '''#!/bin/bash
                    . ./env-config

                    set +x

                    if [[ "${CHART_NAME}" != "${IMAGE_NAME}" ]]; then
                      cp -R "${CHART_ROOT}/${CHART_NAME}" "${CHART_ROOT}/${IMAGE_NAME}"
                      cat "${CHART_ROOT}/${CHART_NAME}/Chart.yaml" | \
                          yq w - name "${IMAGE_NAME}" > "${CHART_ROOT}/${IMAGE_NAME}/Chart.yaml"
                    fi

                    CHART_PATH="${CHART_ROOT}/${IMAGE_NAME}"

                    echo "KUBECONFIG=${KUBECONFIG}"

                    RELEASE_NAME="${IMAGE_NAME}"
                    echo "RELEASE_NAME: $RELEASE_NAME"

                    echo "INITIALIZING helm with client-only (no Tiller)"
                    helm init --client-only 1> /dev/null 2> /dev/null

                    echo "CHECKING CHART (lint)"
                    helm lint ${CHART_PATH}

                    IMAGE_REPOSITORY="${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}"
                    PIPELINE_IMAGE_URL="${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_VERSION}"

                    INGRESS_ENABLED="true"
                    ROUTE_ENABLED="false"
                    if [[ "${CLUSTER_TYPE}" == "openshift" ]]; then
                        INGRESS_ENABLED="false"
                        ROUTE_ENABLED="true"
                    fi

                    # Update helm chart with repository and tag values
                    cat ${CHART_PATH}/values.yaml | \
                        yq w - image.repository "${IMAGE_REPOSITORY}" | \
                        yq w - image.tag "${IMAGE_VERSION}" | \
                        yq w - ingress.enabled "${INGRESS_ENABLED}" | \
                        yq w - route.enabled "${ROUTE_ENABLED}" > ./values.yaml.tmp
                    cp ./values.yaml.tmp ${CHART_PATH}/values.yaml
                    cat ${CHART_PATH}/values.yaml

                    # Using 'upgrade --install" for rolling updates. Note that subsequent updates will occur in the same namespace the release is currently deployed in, ignoring the explicit--namespace argument".
                    helm template ${CHART_PATH} \
                        --name ${RELEASE_NAME} \
                        --namespace ${ENVIRONMENT_NAME} \
                        --set ingress.tlsSecretName="${TLS_SECRET_NAME}" \
                        --set ingress.subdomain="${INGRESS_SUBDOMAIN}" > ./release.yaml

                    echo -e "Generated release yaml for: ${CLUSTER_NAME}/${ENVIRONMENT_NAME}."
                    cat ./release.yaml

                    echo -e "Deploying into: ${CLUSTER_NAME}/${ENVIRONMENT_NAME}."
                    kubectl apply -n ${ENVIRONMENT_NAME} -f ./release.yaml --validate=false
                '''
            }
            stage('Health Check') {
                sh '''#!/bin/bash
                    . ./env-config

                    if [[ "${CLUSTER_TYPE}" == "openshift" ]]; then
                        ROUTE_HOST=$(kubectl get route/${IMAGE_NAME} --namespace ${ENVIRONMENT_NAME} --output=jsonpath='{ .spec.host }')
                        URL="https://${ROUTE_HOST}"
                    else
                        INGRESS_HOST=$(kubectl get ingress/${IMAGE_NAME} --namespace ${ENVIRONMENT_NAME} --output=jsonpath='{ .spec.rules[0].host }')
                        URL="http://${INGRESS_HOST}"
                    fi

                    # sleep for 10 seconds to allow enough time for the server to start
                    sleep 30

                    if [[ $(curl -sL -w "%{http_code}\\n" "${URL}/health" -o /dev/null --connect-timeout 3 --max-time 5 --retry 3 --retry-max-time 30) == "200" ]]; then
                        echo "Successfully reached health endpoint: ${URL}/health"
                        echo "====================================================================="
                    else
                        echo "Could not reach health endpoint: ${URL}/health"
                        exit 1
                    fi

                '''
            }
        }
    }
}
