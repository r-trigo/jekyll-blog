---
layout: post
title: The 6 Aspects You Must Secure On Your MongoDB Instances
tags: database, mongodb, security
date: 2020-12-01 17:15 +0000
---
:information_desk_person: :oncoming_police_car: :leaves:

>Originally published at [Jscrambler Blog](https://blog.jscrambler.com/the-6-aspects-you-must-secure-on-your-mongodb-instances/)

## Prologue
After going through the adventure of [deploying a high-availability MongoDB cluster on Docker][1] and sharing it publicly, I decided to complement that tutorial with some security concerns and tips.

In this post, you'll learn a few details about MongoDB deployment vulnerabilities and security mechanisms. And more importantly, how to actually protect your data with these features.

## Objectives
- understand database aspects of security.
- find ways to implement authentication, authorization, and accounting ([AAA][2]).
- learn how to enable MongoDB security features.

## Pre-requisites
Any running MongoDB instance on which you have full access will do. Standalone or replica set, containerized or not. We will also mention some details on MongoDB Docker instances, but we’ll keep Docker-specific security tips for another post.

## List of Quick Wins
Accessing data in a database has several stages. We will take a look at these stages and find ways to harden them, to get a cumulative security effect at the end. Each of these stages will, most of the time, have the ability to block the next one (e.g. you need to have network access to get to the authentication part).

### 1. Network access
MongoDB’s default port is 27017 (TCP). Choosing a different port to operate might confuse some hackers, but it is still a minor security action because of port scanning, so you won't get that much out of it.

Assuming we choose the default port for our service, we will open that port on the database server's firewall. We do not wish to expose the traffic from this port to the internet. There are two approaches to solve that and both can be used simultaneously. One is limiting your traffic to your trusted servers through firewall configuration.

There’s a MongoDB feature you can use for this: [IP Binding][3]. You pass the `--bind_ip` argument on the MongoDB launch command to enable it. Let's say your `app1` server needs to access the MongoDB server for data. To limit traffic for that specific server, you start your server as:

```bash
mongod --bind_ip localhost,app1
```

If you are using Docker, you can avoid this risk by using a Docker network between your database and your client application.

You can add another layer of network security by creating a dedicated network segment for databases, in which you apply an ACL (access list) in the router and/or switch configuration.

### 2. System access
The second A in AAA means authorization. We know privileged shell access is needed during database installation. When concluding the installation, locking system root user access is part of the drill.

Data analysts need to read database data and applications also need to read and (almost always) write data as well. As this can be addressed with database authentication (more on this on **4. Authorization**), make sure to restrict root and other shell access to people who can't do their jobs without it. Only allow it for database and system administrators.

Furthermore, running MongoDB processes with a dedicated operating system user account is a good practice. Ensure that this account has permission to access data but no unnecessary permissions.

### 3. Authentication
Authentication is the first A in AAA. Authentication-wise, MongoDB supports 4 mechanisms:

- SCRAM (default)
- x.509 certificate authentication
- LDAP proxy authentication
- Kerberos authentication

If you are using [MongoDB Enterprise Server][4], then you can benefit from LDAP and Kerberos support. Integrating your company identity and access management tool will make AAA 3rd A (Accounting) implementation easier, as every user will have a dedicated account associated with his records.

MongoDB has [its own SCRAM implementations][5]: **SCRAM_SHA1** for versions below 4.0 and **SCRAM_SHA256** for 4.0 and above. You can think of [SHA-256 as the successor of SHA-1][6], so pick the latter if available on your database version.

Replica sets [keyfiles][7] also use the SCRAM authentication mechanism where these keyfiles contain the shared password between the replica set members. Another internal authentication mechanism supported in replica sets is x.509. You can read more on replica sets and how to generate keyfiles on our previous [blog post][1].

To be able to use the x.509 certificates authentication mechanism, there are some [requirements regarding certificate attributes][8]. To enable x.509 authentication, add `--tlsMode`, `--tlsCertificateKeyFile` and `--tlsCAFile` (in case the certificate has a certificate authority). To perform remote connections to the database, specify the `--bind_ip`.

```bash
mongod --tlsMode requireTLS --tlsCertificateKeyFile <path to TLS/SSL certificate and key PEM file> --tlsCAFile <path to root CA PEM file> --bind_ip <hostnames>
```

To generate these certificates, you can use the `openssl` library on Linux or the equivalent on other operating systems.

```bash
openssl x509 -in <pathToClientPEM> -inform PEM -subject -nameopt RFC2253
```

The command returns the subject string as well as the certificate:
```bash
subject= CN=myName,OU=myOrgUnit,O=myOrg,L=myLocality,ST=myState,C=myCountry
-----BEGIN CERTIFICATE-----
# ...
-----END CERTIFICATE-----
```

Next, add a user on the **$external** database using the obtained **subject** string like in the example below:

```js
db.getSiblingDB("$external").runCommand(
  {
    createUser: "CN=myName,OU=myOrgUnit,O=myOrg,L=myLocality,ST=myState,C=myCountry",
    roles: [
         { role: "readWrite", db: "test" },
         { role: "userAdminAnyDatabase", db: "admin" }
    ],
    writeConcern: { w: "majority" , wtimeout: 5000 }
  }
)
```

Finally, connect to the database with the arguments for TLS, certificates location, CA file location, authentication database, and the authentication mechanism.

```bash
mongo --tls --tlsCertificateKeyFile <path to client PEM file> --tlsCAFile <path to root CA PEM file>  --authenticationDatabase '$external' --authenticationMechanism MONGODB-X509
```

You have now successfully connected to your database using the x.509 authentication mechanism.

### 4. Authorization
For non-testing environments (like production) it is clearly not recommended to have [Access Control][9] disabled, as this grants all privileges to any successful access to the database. To enable authentication, follow the procedure below.

```bash
# start MongoDB without access control
mongod
# connect to the instance
mongo
```
```js
// create the user administrator
use admin
db.createUser(
  {
    user: "myUserAdmin",
    pwd: passwordPrompt(), // or cleartext password
    roles: [ { role: "userAdminAnyDatabase", db: "admin" }, "readWriteAnyDatabase" ]
  }
)
// shutdown mongod instance
db.adminCommand( { shutdown: 1 } )
```
```bash
# start MongoDB with access control
mongo --auth
```

If you're using [MongoDB on Docker][10], you can create an administrator through `MONGO_INITDB_ROOT_USERNAME` and `MONGO_INITDB_ROOT_PASSWORD` environment variables (`-e` argument). Like so:

```bash
docker run -d -e MONGO_INITDB_ROOT_USERNAME=<username> -e MONGO_INITDB_ROOT_PASSWORD=<password> mongo:4.4
```

Do not neglect human usability convenience. Make sure all [passwords are strong][11], fit your company's password policy, and are stored securely.

MongoDB has a set of [built-in roles][12] and allows us to [create new ones][13]. Use roles to help when giving privileges while applying the [principle of least privilege][14] on user accounts and avoid user account abuse.

### 5. Encrypted connections
Let's now see how to configure encrypted connections to protect you from [sniffing attacks][15].

If you think about internet browsers, you notice how they keep pressing for users to navigate on sites that support HTTP over TLS, also known as [HTTPS][16]. That enforcement exists for a reason: sensitive data protection, both for the client and the server. TLS is therefore protecting this sensitive data during the client-server communication, bidirectionally.

We have explained how to use TLS certificates on **4. Authentication** and now we will see how to encrypt our communications between the database server and a client app through TLS configuration on the application’s MongoDB driver.

First, to configure the MongoDB server to require our TLS certificate, add the `--tlsMode` and `--tlsCertificateKeyFile` arguments:

```bash
mongod --tlsMode requireTLS --tlsCertificateKeyFile <pem>
```

To test the connection to mongo shell, type in:

```bash
mongo --tls --host <hostname.example.com> --tlsCertificateKeyFile <certificate_key_location>
```

Then, add TLS options to the database connection on your application code. Here is a snippet of a NodeJS application using MongoDB’s official driver package. You can find more of these encryption options on the [driver documentation][17].

```js
const MongoClient = require('mongodb').MongoClient;
const fs = require('fs');

// Read the certificate authority
const ca = [fs.readFileSync(__dirname + "/ssl/ca.pem")];

const client = new MongoClient('mongodb://localhost:27017?ssl=true', {
  sslValidate:true,
  sslCA:ca
});

// Connect validating the returned certificates from the server
client.connect(function(err) {
  client.close();
});
```

### 6. Encryption at rest
[MongoDB Enterprise Server][4] comes with an [Encryption at Rest][18] feature. Through a master and database keys system, this allows us to store our data in an encrypted state by configuring the field as encrypted on rest. You can learn more about the supported standards and enciphering/deciphering keys on the [MongoDB documentation][19].

On the other side, if you will stick with the [MongoDB Community][20], on v4.2 MongoDB started supporting [Client-Side Field Level Encryption][21]. Here’s how it works: you generate the necessary keys and load them in your [database driver][22] (e.g. NodeJS MongoDB driver). Then, you will be able to encrypt your data before storing it in the database and decrypt it for your application to read it.

Below, you can find a JavaScript code snippet showing data encryption and decryption happening on MongoDB’s NodeJS driver with the help of the npm package [mongodb-client-encryption][23].

```js
const unencryptedClient = new MongoClient(URL, { useUnifiedTopology: true });
  try {
    await unencryptedClient.connect();
    const clientEncryption = new ClientEncryption(unencryptedClient, { kmsProviders, keyVaultNamespace });

    async function encryptMyData(value) {
      const keyId = await clientEncryption.createDataKey('local');
      console.log("keyId", keyId);
      return clientEncryption.encrypt(value, { keyId, algorithm: 'AEAD_AES_256_CBC_HMAC_SHA_512-Deterministic' });
    }

    async function decryptMyValue(value) {
      return clientEncryption.decrypt(value);
    }

    const data2 = await encryptMyData("sensitive_data");
    const mKey = key + 1;
    const collection = unencryptedClient.db("test").collection('coll');
    await collection.insertOne({ name: data2, key: mKey });
    const a = await collection.findOne({ key: mKey });
    console.log("encrypted:", a.name);
    const decrypteddata = await decryptMyValue(a.name);
    console.log("decrypted:", decrypteddata);

  } finally {
    await unencryptedClient.close();
  }
```

## Conclusion
While this post attempts to cover some of the most important quick wins you can achieve to secure your MongoDB instances, there is much more to MongoDB security.

Upgrading database and driver versions frequently, connecting a monitoring tool, and keeping track of database access and configuration are also good ideas to increase security.

Nevertheless, even if the system was theoretically entirely secured, it is always prone to human mistakes. Make sure the people working with you are conscious of the importance of keeping data secured - properly securing a system is always contingent on all users taking security seriously..

Security is everyone's job. Like in tandem kayaks, it only makes sense if everyone is paddling together in the same direction, with all efforts contributing to the same purpose.

[1]: https://blog.jscrambler.com/how-to-achieve-mongo-replication-on-docker/
[2]: https://en.wikipedia.org/wiki/AAA_(computer_security)
[3]: https://docs.mongodb.com/manual/core/security-mongodb-configuration/
[4]: https://www.mongodb.com/try/download/enterprise
[5]: https://docs.mongodb.com/manual/core/security-scram/#scram
[6]: https://www.thesslstore.com/blog/difference-sha-1-sha-2-sha-256-hash-algorithms/
[7]: https://docs.mongodb.com/manual/core/security-internal-authentication/#keyfiles
[8]: https://docs.mongodb.com/manual/tutorial/configure-x509-client-authentication/#client-x-509-certificate
[9]: https://docs.mongodb.com/manual/tutorial/enable-authentication/
[10]: https://hub.docker.com/_/mongo
[11]: https://www.webroot.com/us/en/resources/tips-articles/how-do-i-create-a-strong-password
[12]: https://docs.mongodb.com/manual/reference/built-in-roles/
[13]: https://docs.mongodb.com/manual/tutorial/manage-users-and-roles/#create-a-user-defined-role
[14]: https://en.wikipedia.org/wiki/Principle_of_least_privilege
[15]: https://en.wikipedia.org/wiki/Sniffing_attack
[16]: https://en.wikipedia.org/wiki/HTTPS
[17]: http://mongodb.github.io/node-mongodb-native/3.1/tutorials/connect/ssl/
[18]: https://docs.mongodb.com/manual/core/security-encryption-at-rest/
[19]: https://docs.mongodb.com/manual/core/security-encryption-at-rest/#encryption-process
[20]: https://www.mongodb.com/try/download/community
[21]: https://docs.mongodb.com/manual/core/security-client-side-encryption/
[22]: https://docs.mongodb.com/drivers/
[23]: https://www.npmjs.com/package/mongodb-client-encryption

<link rel="canonical" href="https://blog.jscrambler.com/the-6-aspects-you-must-secure-on-your-mongodb-instances/" />
