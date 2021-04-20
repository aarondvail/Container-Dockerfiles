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
                git 'https://github.com/aarondvail/Container-Dockerfiles.git' 
            }
        }
        stage('Build image') {
            steps { 
                script { 
                    def dockerfile = "${BRANCH_NAME}.dockerfile"
                    echo "dockerImage = docker.build (\"${registry}:${BUILD_NUMBER}\", \"-f ${dockerfile}\")" 
                    dockerImage = docker.build ("${registry}:${BUILD_NUMBER}", "-f ${dockerfile} .") 
                    dockerImageLatest = docker.build ("${registry}:latest", "-f ${dockerfile} .") 
                }
            } 
        }
        stage('Deploy our image') { 
            steps { 
                script { 
                    docker.withRegistry( '', registryCredential ) { 
                        dockerImage.push() 
                        dockerImageLatest.push() 
                    }
                } 
            }
        } 
        stage('Cleaning up') { 
            steps { 
                sh "docker rmi $registry:$BUILD_NUMBER" 
                sh "docker rmi $registry:latest" 
            }
        } 
    }
}
