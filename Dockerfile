# Use the official lightweight Node.js 12 image.
# https://hub.docker.com/_/node
FROM node:12-slim as builder

# Create and change to the app directory.
WORKDIR /usr/src/app

# Copy application dependency manifests to the container image.
# A wildcard is used to ensure both package.json AND package-lock.json are copied.
# Copying this separately prevents re-running npm install on every code change.
COPY package*.json ./

# Install dependencies.
RUN npm install

# Copy local code to the container image.
COPY . ./

# Build next js
RUN npm run export

# export
FROM nginx:1.20.1

COPY --from=builder /usr/src/app/out /www/example

WORKDIR /www/example

COPY ./config/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
