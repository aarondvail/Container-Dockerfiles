pipeline {
    environment { 
        registry = "aarondvail/$BRANCH_NAME" 
        registryCredential = 'DockerHub' 
        dockerImage = '' 
    }
    agent any
    //triggers {
    //    cron('0 2 * * 3')
    //}
    parameters {
        string(name: 'VERSION_NUMBER', defaultValue: '', description: 'Enter the Version Number for a manual run')
    }
    stages { 
        stage('Clone repository') {
            steps { 
                withCredentials([usernamePassword(credentialsId: 'Github', usernameVariable: 'Username', passwordVariable: 'Password')]) {
                    git 'https://github.com/aarondvail/Container-Dockerfiles.git' 
                    sh "find . -name \"*.sh\" -exec chmod +x {} \\;"
                }
            }
        }
//    stage('SonarQube Analysis') {
//            def scannerHome = tool 'SonarScanner';
//        withSonarQubeEnv() {
//                  sh "${scannerHome}/bin/sonar-scanner"
//        }
//    }
    stage('Buildx image') {
            steps { 
                script { 
                    def dockerfile = "${BRANCH_NAME}.dockerfile"
                    // Docker Hub repository names must be lowercase (branch OpenTAKServer -> aarondvail/opentakserver)
                    def image = registry.toLowerCase()
                    echo "${image}:${BUILD_NUMBER} - ${dockerfile}" 
                    if (dockerfile == "minecraftbedrock.dockerfile"){
                        withCredentials([usernamePassword(credentialsId: 'Nexus_Integration', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASS')]) {
                            sh "curl --output bedrock-server-${VERSION_NUMBER}.zip 'http://172.16.248.11:8092/repository/minecraft/${VERSION_NUMBER}/bedrock-server-${VERSION_NUMBER}.zip'"
                        }
                    }
                    docker.withRegistry( '', registryCredential ) { 
                        sh "docker run --rm --privileged docker/binfmt:820fdd95a9972a5308930a2bdfb8573dd4447ad3"
                        sh "docker buildx prune -f"
                        sh "docker buildx inspect mybuilder >/dev/null 2>&1 || docker buildx create --name mybuilder"
                        sh "docker buildx use mybuilder"
                        // One build, two tags: the version (or build number) and latest
                        def versionTag = ("${VERSION_NUMBER}" == '') ? "${BUILD_NUMBER}" : "${VERSION_NUMBER}"
                        sh "docker buildx build --build-arg VERSION_NUMBER=${VERSION_NUMBER} --platform=linux/amd64 --tag ${image}:${versionTag} --tag ${image}:latest -f ${dockerfile} . --push"
                    }
                }
            } 
        }
        stage('Cleaning up') { 
            steps { 
                //sh "docker rmi $registry:latest" 
                deleteDir()
            }
        } 
    }
}
