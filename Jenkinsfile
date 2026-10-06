pipeline {
    agent {
        node {
            label 'docker-multi-agent'
        }
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
        ansiColor('xterm')
    }

    parameters {
        string(
            name: 'RELEASE_VERSION',
            defaultValue: '1.0.1-RELEASE',
            description: 'Target release or snapshot version to deploy from Gitea Package Registry (e.g. 1.0.1-RELEASE, 1.0.1-SNAPSHOT)'
        )
        string(
            name: 'TARGET_HOST',
            defaultValue: '192.168.1.235',
            description: 'Target dev-server-vm IP or hostname'
        )
        string(
            name: 'TARGET_PORT',
            defaultValue: '22',
            description: 'SSH port for target host'
        )
        string(
            name: 'DEPLOY_PATH',
            defaultValue: '/opt/petstore',
            description: 'Deployment destination directory on target server'
        )
        string(
            name: 'SSH_USER',
            defaultValue: 'jenkins',
            description: 'SSH user configured on target server'
        )
    }

    environment {
        // Gitea Configuration
        GITEA_URL                  = 'http://192.168.1.233'
        GITEA_PACKAGE_OWNER        = 'ProdHome'
        
        // Credentials IDs
        GITEA_TOKEN_CRED_ID        = 'gitea-token'        // Secret text (Gitea PAT for package registry)
        DEV_SERVER_SSH_CRED_ID     = 'dev-server-ssh-key' // SSH Username with private key for target host
    }

    stages {
        stage('Fetch Artifacts from Gitea Package Registry') {
            steps {
                script {
                    def version = params.RELEASE_VERSION.trim()
                    def cleanVersion = version.startsWith('v') ? version.substring(1) : version
                    echo "=== Fetching Pet Store Artifacts for Version: ${cleanVersion} from Gitea (${env.GITEA_PACKAGE_OWNER}) ==="

                    withCredentials([string(credentialsId: env.GITEA_TOKEN_CRED_ID, variable: 'GITEA_TOKEN')]) {
                        sh """
                            set -e
                            mkdir -p backend frontend

                            WAR_URL="${env.GITEA_URL}/api/packages/${env.GITEA_PACKAGE_OWNER}/maven/com/petstore/pet-store-web/${cleanVersion}/pet-store-web-${cleanVersion}.war"
                            ZIP_URL="${env.GITEA_URL}/api/packages/${env.GITEA_PACKAGE_OWNER}/maven/com/petstore/pet-store-frontend/${cleanVersion}/pet-store-frontend-${cleanVersion}.zip"

                            echo "Downloading backend WAR from: \${WAR_URL}..."
                            curl -f -s -L -H "Authorization: token \${GITEA_TOKEN}" -o backend/petstore.war "\${WAR_URL}"

                            echo "Downloading frontend ZIP from: \${ZIP_URL}..."
                            curl -f -s -L -H "Authorization: token \${GITEA_TOKEN}" -o frontend/pet-store-frontend.zip "\${ZIP_URL}"

                            echo "Artifacts successfully fetched:"
                            ls -lh backend/petstore.war frontend/pet-store-frontend.zip
                        """
                    }
                }
            }
        }

        stage('Deploy to Target VM via SSH & Docker Compose') {
            steps {
                script {
                    def targetHost = params.TARGET_HOST.trim()
                    def targetPort = params.TARGET_PORT ? params.TARGET_PORT.trim() : '22'
                    def deployPath = params.DEPLOY_PATH.trim()
                    def sshUser = params.SSH_USER.trim()

                    echo "=== Deploying to ${sshUser}@${targetHost}:${targetPort} at ${deployPath} ==="

                    withCredentials([sshUserPrivateKey(credentialsId: env.DEV_SERVER_SSH_CRED_ID, keyFileVariable: 'SSH_KEY')]) {
                        sh """
                            set -e
                            export SSH_OPTS="-i \${SSH_KEY} -p ${targetPort} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
                            export SCP_OPTS="-i \${SSH_KEY} -P ${targetPort} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

                            echo "Ensuring deployment directory structure on ${sshUser}@${targetHost}..."
                            ssh \${SSH_OPTS} ${sshUser}@${targetHost} "mkdir -p ${deployPath}/backend/conf ${deployPath}/frontend ${deployPath}/scripts"

                            echo "Transferring Docker compose & service manifests..."
                            scp \${SCP_OPTS} docker-compose.yml ${sshUser}@${targetHost}:${deployPath}/docker-compose.yml
                            scp \${SCP_OPTS} .env.example ${sshUser}@${targetHost}:${deployPath}/.env.example
                            scp \${SCP_OPTS} backend/Dockerfile ${sshUser}@${targetHost}:${deployPath}/backend/Dockerfile
                            scp \${SCP_OPTS} backend/conf/application.properties ${sshUser}@${targetHost}:${deployPath}/backend/conf/application.properties
                            scp \${SCP_OPTS} frontend/Dockerfile ${sshUser}@${targetHost}:${deployPath}/frontend/Dockerfile
                            scp \${SCP_OPTS} frontend/httpd.conf ${sshUser}@${targetHost}:${deployPath}/frontend/httpd.conf
                            scp \${SCP_OPTS} scripts/deploy.sh ${sshUser}@${targetHost}:${deployPath}/scripts/deploy.sh

                            echo "Transferring application artifacts..."
                            scp \${SCP_OPTS} backend/petstore.war ${sshUser}@${targetHost}:${deployPath}/backend/petstore.war
                            scp \${SCP_OPTS} frontend/pet-store-frontend.zip ${sshUser}@${targetHost}:${deployPath}/frontend/pet-store-frontend.zip

                            echo "Running deployment script on target host..."
                            ssh \${SSH_OPTS} ${sshUser}@${targetHost} "chmod +x ${deployPath}/scripts/deploy.sh && cd ${deployPath} && ./scripts/deploy.sh --local"
                        """
                    }
                }
            }
        }

        stage('Verify Deployment Health') {
            steps {
                script {
                    def targetHost = params.TARGET_HOST.trim()
                    echo "=== Verifying Application Health on http://${targetHost} ==="

                    // Verify frontend and backend API endpoints from agent
                    sh """
                        set -e
                        echo "Checking Frontend SPA..."
                        curl -f -s -m 5 http://${targetHost}/ > /dev/null
                        echo "Frontend is accessible at http://${targetHost}"

                        echo "Checking Backend REST API..."
                        curl -f -s -m 5 http://${targetHost}/api/pets > /dev/null
                        echo "Backend API is responding at http://${targetHost}/api/pets"
                    """

                    echo "=================================================================="
                    echo " DEPLOYMENT SUCCESSFUL!"
                    echo " Version:   ${params.RELEASE_VERSION}"
                    echo " Host:      http://${targetHost}"
                    echo " API:       http://${targetHost}/api/pets"
                    echo "=================================================================="
                }
            }
        }
    }

    post {
        always {
            // Clean downloaded binary artifacts from agent workspace
            sh 'rm -f backend/petstore.war frontend/pet-store-frontend.zip'
        }
        success {
            echo "CD Pipeline finished successfully for version ${params.RELEASE_VERSION}."
        }
        failure {
            echo "CD Pipeline failed. Check console log for details."
        }
    }
}
