pipeline {
    environment { 
        registry = "aarondvail/$BRANCH_NAME" 
        registryCredential = 'DockerHub' 
        dockerImage = '' 
    }
    agent any 
    stages { 
        stage('Clone repository') {
            steps { 
                withCredentials([usernamePassword(credentialsId: 'Github', usernameVariable: 'Username', passwordVariable: 'Password')]) {
					git 'https://github.com/aarondvail/Container-Dockerfiles.git' 
					sh "find . -name \"*.sh\" -exec chmod +x {} \\;"
				}
            }
        }
        stage('Buildx image') {
            steps { 
                script { 
                    def dockerfile = "${BRANCH_NAME}.dockerfile"
                    echo "${registry}:${amd64tag} - ${dockerfile}" 
                    docker.withRegistry( '', registryCredential ) { 
                        sh "docker run --rm --privileged docker/binfmt:820fdd95a9972a5308930a2bdfb8573dd4447ad3"
                        sh "docker buildx create --name mybuilder"
                        sh "docker buildx use mybuilder"
                        sh "docker buildx build --platform=linux/arm64,linux/amd64 --tag ${registry}:${BUILD_NUMBER} -f ${dockerfile} . --push"
                        sh "docker buildx build --platform=linux/arm64,linux/amd64 --tag ${registry}:latest -f ${dockerfile} . --push"
                    }
                }
            } 
        }
        stage('Cleaning up') { 
            steps { 
                sh "docker rmi $registry:latest" 
                deleteDir()
            }
        } 
    }
}
