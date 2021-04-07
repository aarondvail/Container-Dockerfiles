pipeline {
    def app
    environment { 
        registry = "aarondvail/test" 
        registryCredential = 'DockerHub' 
        dockerImage = '' 
    }
    agent any 
    stages { 
        stage('Clone repository') {
            checkout scm
        }
        stage('Build image') {
            dockerImage = docker.build registry + ":$BUILD_NUMBER"
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
