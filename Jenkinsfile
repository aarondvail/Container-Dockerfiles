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
                    echo "dockerImage = docker.build registry + :$BUILD_NUMBER -f $WORKSPACE/$BRANCH_NAME.dockerfile" 
                    dockerImage = docker.build registry + ":$BUILD_NUMBER -f $WORKSPACE/$BRANCH_NAME.dockerfile" 
                    dockerImageLatest = docker.build registry + ":latest -f $WORKSPACE/$BRANCH_NAME.dockerfile" 
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
