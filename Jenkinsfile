pipeline {
    environment { 
        registry = "aarondvail/test" 
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
                    dockerImage = docker.build registry + ":$BUILD_NUMBER" 
                    dockerImage = docker.build registry + ":latest" 
                }
            } 
        }
        stage('Deploy our image') { 
            steps { 
                script { 
                    docker.withRegistry( '', registryCredential ) { 
                        dockerImage.push() 
                    }
                } 
            }
        } 
        stage('Cleaning up') { 
            steps { 
                sh "docker rmi $registry:$BUILD_NUMBER" 
            }
        } 
    }
}
