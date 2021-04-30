pipeline {
    environment { 
        registry = "aarondvail/$BRANCH_NAME" 
        registryCredential = 'DockerHub' 
        dockerImage = '' 
        amd64tag = "amd64-${BUILD_NUMBER}"
        arm32v7tag = "arm32v7-${BUILD_NUMBER}"
        arm64v8tag = "arm64v8-${BUILD_NUMBER}"
    }
    agent any 
    stages { 
        stage('Clone repository') {
            steps { 
                git 'https://github.com/aarondvail/Container-Dockerfiles.git' 
				sh "find . -name "*.sh" -exec chmod +x {} \;"
            }
        }
//        stage('Build image') {
//            steps { 
//                script { 
//                    def dockerfile = "${BRANCH_NAME}.dockerfile"
//                    echo "dockerImage = docker.build (\"${registry}:${BUILD_NUMBER}\", \"-f ${dockerfile} .\")" 
//                    dockerImage = docker.build ("${registry}:${BUILD_NUMBER}", "-f ${dockerfile} .") 
//                    dockerImageLatest = docker.build ("${registry}:latest", "-f ${dockerfile} .") 
//                }
//            } 
//        }
//        stage('Buildx image') {
//            steps { 
//                script { 
//                    def dockerfile = "${BRANCH_NAME}.dockerfile"
//                    echo "${registry}:${amd64tag} - ${dockerfile}" 
//                    docker.withRegistry( '', registryCredential ) { 
//                        sh "docker buildx create --use --name ${BRANCH_NAME} node-amd64"
//                        sh "docker buildx create --append --name ${BRANCH_NAME} node-arm64"
//                        sh "docker buildx create --append --name ${BRANCH_NAME} node-arm"
//                        sh "docker buildx build --platform=linux/arm/v7,linux/arm64/v8,linux/amd64 --tag ${registry}:latest -f ${dockerfile} ."
//                    }
//                }
//            } 
//        }
        stage('Build amd64 image') {
            steps { 
                script { 
                    def dockerfile = "${BRANCH_NAME}.dockerfile"
                    echo "${registry}:${amd64tag} - ${dockerfile}" 
                    sh "docker build -t ${registry}:${amd64tag} --build-arg ARCH=amd64/ -f ${dockerfile} ." 
                    docker.withRegistry( '', registryCredential ) { 
                        sh "docker push ${registry}:${amd64tag}"
                    }
                }
            } 
        }
        stage('Build arm32v7 image') {
            steps { 
                script { 
                    def dockerfile = "${BRANCH_NAME}.dockerfile"
                    echo "${registry}:${arm32v7tag} - ${dockerfile}" 
//                    sh "docker build -t ${registry}:${arm32v7tag} --build-arg ARCH=arm32v7/ -f ${dockerfile} ." 
//                    docker.withRegistry( '', registryCredential ) { 
//                        sh "docker push ${registry}:${arm32v7tag}"
//                    }
                }
            } 
        }
        stage('Build arm64v8 image') {
            steps { 
                script { 
                    def dockerfile = "${BRANCH_NAME}.dockerfile"
                    echo "${registry}:${arm64v8tag} - ${dockerfile}" 
//                    sh "docker build -t ${registry}:${arm64v8tag} --build-arg ARCH=arm64v8/ -f ${dockerfile} ." 
//                    docker.withRegistry( '', registryCredential ) { 
//                        sh "docker push ${registry}:${arm64v8tag}" 
//                    }
                }
            } 
        }
//        stage('Deploy our image') { 
//            steps { 
//                script { 
//                    docker.withRegistry( '', registryCredential ) { 
//                        dockerImage.push() 
//                        dockerImageLatest.push() 
//                    }
//                } 
//            }
//        } 
        stage('Create Manifest List and Deploy') { 
            steps { 
                script {
                    docker.withRegistry( '', registryCredential ) { 
//                        sh "docker manifest create ${registry}:latest --amend ${registry}:${amd64tag} --amend ${registry}:${arm32v7tag} --amend ${registry}:${arm64v8tag}"
                        sh "docker manifest create ${registry}:latest --amend ${registry}:${amd64tag}"
                        sh "docker manifest push ${registry}:latest"
                    }
                } 
            }
        } 
//        stage('Deploy our Manifest') { 
//            steps { 
//                script { 
//                    docker.withRegistry( '', registryCredential ) { 
//                        sh "docker manifest push ${registry}:latest" 
//                    }
//                } 
//            }
//        } 
        stage('Cleaning up') { 
            steps { 
//                sh "docker rmi ${registry}:${amd64tag}" 
//                sh "docker rmi ${registry}:${arm32v7tag}" 
//                sh "docker rmi ${registry}:${arm64v8tag}" 
//                sh "docker rmi $registry:latest" 
                deleteDir()
            }
        } 
    }
}
