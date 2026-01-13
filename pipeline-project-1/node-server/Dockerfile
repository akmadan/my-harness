# Use Node.js LTS version for AMD64
FROM --platform=linux/amd64 node:18-alpine

# Set working directory
WORKDIR /app

# Copy package.json and package-lock.json (if exists)
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application code
COPY . .

# Expose port 3000
EXPOSE 3000

# Run the application
CMD ["node", "index.js"]