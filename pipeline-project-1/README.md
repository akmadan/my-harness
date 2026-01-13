# Build and push Node.js server
docker build --platform linux/amd64 -t akshitmadanharness/pipeline-project-1-node-server:latest ./node-server
docker push akshitmadanharness/pipeline-project-1-node-server:latest

# Build and push React frontend  
docker build --platform linux/amd64 -t akshitmadanharness/pipeline-project-1-react-frontend:latest ./react-frontend
docker push akshitmadanharness/pipeline-project-1-react-frontend:latest