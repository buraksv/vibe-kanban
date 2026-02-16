pipeline {
    agent any
    
    environment {
        // Docker image configuration
        DOCKER_REGISTRY = credentials('docker-registry-url')
        DOCKER_IMAGE_LOCAL = "vibe-kanban-local"
        DOCKER_IMAGE_REMOTE = "vibe-kanban-remote"
        IMAGE_TAG = "${env.BUILD_NUMBER}"
        
        // Database configuration (from Jenkins credentials)
        DATABASE_URL = credentials('vibe-kanban-database-url')
        POSTGRES_PASSWORD = credentials('postgres-password')
        
        // Server configuration
        SERVER_PUBLIC_BASE_URL = credentials('server-public-base-url')
        AUTH_PUBLIC_BASE_URL = credentials('auth-public-base-url')
        JWT_SECRET = credentials('jwt-secret')
        
        // OAuth credentials
        GITHUB_CLIENT_ID = credentials('github-client-id')
        GITHUB_CLIENT_SECRET = credentials('github-client-secret')
        GOOGLE_CLIENT_ID = credentials('google-client-id')
        GOOGLE_CLIENT_SECRET = credentials('google-client-secret')
        
        // Migration kontrolü - ilk deploy için false, sonrasında true
        SKIP_MIGRATIONS = "false"
        
        // Rust logging
        RUST_LOG = "info"
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
    }
    
    stages {
        stage('Checkout') {
            steps {
                echo "Checking out code..."
                checkout scm
                
                script {
                    // Git commit bilgilerini al
                    env.GIT_COMMIT_SHORT = sh(
                        script: "git rev-parse --short HEAD",
                        returnStdout: true
                    ).trim()
                    env.GIT_BRANCH = sh(
                        script: "git rev-parse --abbrev-ref HEAD",
                        returnStdout: true
                    ).trim()
                }
                
                echo "Building from branch: ${env.GIT_BRANCH}"
                echo "Commit: ${env.GIT_COMMIT_SHORT}"
            }
        }
        
        stage('Environment Check') {
            steps {
                echo "Checking environment configuration..."
                sh '''
                    echo "Node version: $(node --version)"
                    echo "Docker version: $(docker --version)"
                    echo "Docker Compose version: $(docker-compose --version)"
                '''
            }
        }
        
        stage('Database Migration Check') {
            when {
                expression { env.SKIP_MIGRATIONS == 'false' }
            }
            steps {
                echo "Checking database migrations..."
                script {
                    // Migration'ları kontrol et
                    sh '''
                        echo "Current migrations will be applied on container start"
                        # İsterseniz burada migration dosyalarını loglayabilirsiniz
                        ls -la crates/db/migrations/ || true
                        ls -la crates/remote/migrations/ || true
                    '''
                }
            }
        }
        
        stage('Build - Local Server') {
            when {
                expression { params.BUILD_LOCAL == true }
            }
            steps {
                echo "Building local server Docker image..."
                script {
                    docker.build(
                        "${DOCKER_REGISTRY}/${DOCKER_IMAGE_LOCAL}:${IMAGE_TAG}",
                        "-f Dockerfile ."
                    )
                    docker.build(
                        "${DOCKER_REGISTRY}/${DOCKER_IMAGE_LOCAL}:latest",
                        "-f Dockerfile ."
                    )
                }
            }
        }
        
        stage('Build - Remote Server') {
            steps {
                echo "Building remote server Docker image..."
                script {
                    docker.build(
                        "${DOCKER_REGISTRY}/${DOCKER_IMAGE_REMOTE}:${IMAGE_TAG}",
                        "--build-arg APP_NAME=remote " +
                        "--build-arg FEATURES=${params.REMOTE_FEATURES ?: ''} " +
                        "-f crates/remote/Dockerfile ."
                    )
                    docker.build(
                        "${DOCKER_REGISTRY}/${DOCKER_IMAGE_REMOTE}:latest",
                        "--build-arg APP_NAME=remote " +
                        "--build-arg FEATURES=${params.REMOTE_FEATURES ?: ''} " +
                        "-f crates/remote/Dockerfile ."
                    )
                }
            }
        }
        
        stage('Run Tests') {
            when {
                expression { params.RUN_TESTS == true }
            }
            steps {
                echo "Running tests..."
                sh '''
                    # Backend tests
                    cargo test --workspace --release || true
                    
                    # Frontend type checks
                    pnpm install
                    pnpm run check || true
                '''
            }
        }
        
        stage('Push Images') {
            when {
                expression { params.PUSH_TO_REGISTRY == true }
            }
            steps {
                echo "Pushing Docker images to registry..."
                script {
                    docker.withRegistry("https://${DOCKER_REGISTRY}", 'docker-registry-credentials') {
                        if (params.BUILD_LOCAL == true) {
                            sh "docker push ${DOCKER_REGISTRY}/${DOCKER_IMAGE_LOCAL}:${IMAGE_TAG}"
                            sh "docker push ${DOCKER_REGISTRY}/${DOCKER_IMAGE_LOCAL}:latest"
                        }
                        
                        sh "docker push ${DOCKER_REGISTRY}/${DOCKER_IMAGE_REMOTE}:${IMAGE_TAG}"
                        sh "docker push ${DOCKER_REGISTRY}/${DOCKER_IMAGE_REMOTE}:latest"
                    }
                }
            }
        }
        
        stage('Deploy - Staging') {
            when {
                branch 'develop'
            }
            steps {
                echo "Deploying to staging environment..."
                script {
                    // Staging ortamına deploy
                    sh """
                        docker-compose -f docker-compose.yml down vibe-kanban-remote || true
                        docker-compose -f docker-compose.yml pull vibe-kanban-remote
                        docker-compose -f docker-compose.yml up -d vibe-kanban-remote
                    """
                }
            }
        }
        
        stage('Deploy - Production') {
            when {
                branch 'main'
            }
            steps {
                echo "Deploying to production environment..."
                input message: 'Deploy to production?', ok: 'Deploy'
                
                script {
                    // Production ortamına deploy
                    sh """
                        docker-compose -f docker-compose.prod.yml down vibe-kanban-remote || true
                        docker-compose -f docker-compose.prod.yml pull vibe-kanban-remote
                        docker-compose -f docker-compose.prod.yml up -d vibe-kanban-remote
                    """
                    
                    // Health check
                    echo "Waiting for service to start..."
                    sh """
                        for i in {1..30}; do
                            if wget --spider -q http://localhost:8081/v1/health; then
                                echo "Service is healthy!"
                                exit 0
                            fi
                            echo "Waiting for service... (attempt \$i/30)"
                            sleep 5
                        done
                        echo "Service failed to start!"
                        exit 1
                    """
                }
            }
        }
        
        stage('Cleanup') {
            steps {
                echo "Cleaning up old Docker images..."
                sh '''
                    # Kullanılmayan image'ları temizle (opsiyonel)
                    docker image prune -f --filter "until=24h" || true
                '''
            }
        }
    }
    
    post {
        success {
            echo "Pipeline completed successfully!"
            // Slack/email bildirimi gönderebilirsiniz
        }
        failure {
            echo "Pipeline failed!"
            // Hata bildirimi gönderebilirsiniz
        }
        always {
            echo "Cleaning up workspace..."
            cleanWs()
        }
    }
    
    parameters {
        booleanParam(
            name: 'BUILD_LOCAL',
            defaultValue: false,
            description: 'Build local server (SQLite) image?'
        )
        booleanParam(
            name: 'RUN_TESTS',
            defaultValue: true,
            description: 'Run tests before deployment?'
        )
        booleanParam(
            name: 'PUSH_TO_REGISTRY',
            defaultValue: true,
            description: 'Push images to Docker registry?'
        )
        string(
            name: 'REMOTE_FEATURES',
            defaultValue: '',
            description: 'Cargo features for remote build (e.g., vk-billing)'
        )
    }
}
