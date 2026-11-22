FROM node:20-slim

WORKDIR /app

# Prisma's query/schema engines require the system OpenSSL libraries at build
# and runtime. node:20-slim does not guarantee that libssl is installed.
RUN apt-get update \
    && apt-get install -y --no-install-recommends openssl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY package*.json ./
COPY prisma ./prisma
RUN npm install && npx prisma generate

COPY . .
RUN npm run build

EXPOSE 3000
CMD ["node", "dist/main.js"]
