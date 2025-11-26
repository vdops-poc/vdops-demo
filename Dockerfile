ARG NODE_VERSION 18-alpine
FROM node:$NODE_VERSION

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .

EXPOSE 3000
CMD ["npm", "start"]

