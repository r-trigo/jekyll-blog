---
layout: post
title: Connecting Sequelize to a PostgreSQL cluster
---
:large_blue_diamond: :elephant: :sheep:

## Prologue

In the [previous post][1] we showed how to automate a PostgreSQL fault-tolerant cluster with Vagrant and Ansible.

This kind of setup makes our database cluster resilient to server failure and keeps the data available with no need for human interaction. What about apps? Are they fault-tolerant too? ORMs like Sequelize have [read replication][10] feature, which allows you to define your primary and standby nodes in the database connection.

What happens if your primary node, which is responsible for write operations, is offline and your app needs to continue saving data into your database?

One way to solve this is adding an extra layer to the system - a load balancing layer - using PostgreSQL 3rd party tools like [pgbouncer][2] or [Pgpool-II][3] or even a properly configured [HAproxy][8] instance. Besides the complexity brought by this solution, you could also be introducing an undesired [single point of failure][9].

Another way is using a floating IP address, or virtual IP address to assign to the current primary database node, so the application knows which node it must connect to when performing write operations.

## Objectives
- connecting a **NodeJS** application with **Sequelize** to a **PostgreSQL** cluster in order to write from primary and read from standby nodes;
- create and assign a **Digital Ocean Floating IP** (aka FLIP) to our current primary database node;
- interact with **Digital Ocean CLI** to reassign FLIP to new primary node;
- keep this switchover transparent to the **NodeJS** application, so the whole system works without human help.

## Pre-requisites
- **PostgreSQL** cluster with **repmgr** (you can follow the [tutorial][1] or just use a cluster with streaming replication and simulate failure + manual promotion)
- **Digital Ocean** account and API token ([create an account][4])
- [NodeJS][5] and [npm][6] installed (I'm using **NodeJS** v12 with **npm** v6)
- a **PostgreSQL** user with password authentication which accepts remote connections from your application host (I'll be using `postgres`:`123456`)

## NodeJS application
Let's write a simple app, which manipulates a `countries` table. Keep in mind [pluralization on Sequelize][7] for Javascript object and default database table names. Set it up with:

```bash
mkdir sequelize-postgresql-cluster
cd sequelize-postgresql-cluster
npm init -y
npm install pg sequelize
```

Now edit `index.js` with the following:

```js
const { Sequelize } = require('sequelize');

const floating_ipv4 = '95.216.180.154'
const primary_ipv4 = '172.16.1.11'
const standby_ipv4 = '172.16.1.12'

const sequelize = new Sequelize('postgres', 'postgres', '123456', {
  dialect: 'postgres',
  port: 5432,
  replication: {
    read: [
      { host: standby_ipv4 },
      { host: primary_ipv4 }
      // witness node has no data, only metadata
    ],
    write: { host: primary_ipv4 }
  },
  pool: {
    max: 10,
    idle: 30000
  },
})

// connect to DB
async function connect() {
  console.log('Checking database connection...');
  try {
    await sequelize.authenticate();
    console.log('Connection has been established successfully.');
  } catch (error) {
    console.error('Unable to connect to the database:', error);
    process.exit(1);
  }
}
```



```js
// model
const Country = sequelize.define('Country', {
  country_id: {
    type: Sequelize.INTEGER, autoIncrement: true, primaryKey: true
  },
  name: Sequelize.STRING,
  is_eu_member: Sequelize.BOOLEAN
},
{
  timestamps: false
});

async function create_table() {
  await sequelize.sync({force: true});
  console.log("create table countries")
};

// insert country
async function insertCountry() {
  const pt = await Country.create({ name: "Portugal", is_eu_member: true });
  console.log("pt created - country_id: ", pt.country_id);
}

// select all countries
async function findAllCountries() {
  const countries = await Country.findAll();
  console.log("All countries:", JSON.stringify(countries, null, 2));
}

async function run() {
  await create_table()
  await insertCountry()
  await findAllCountries()
  await sequelize.close();
}

run()
```

## Normal situation test

## Digital Ocean CLI configuration

## Add script to repmgr promote command

## Primary failure test

[1]: https://blog.jscrambler.com/how-to-automate-postgresql-and-repmgr-on-vagrant/
[2]: https://m.do.co/c/x
[3]: http://www.pgbouncer.org/
[4]: https://wiki.postgresql.org/wiki/Pgpool-II
[5]: https://nodejs.org/en/download/
[6]: https://www.npmjs.com/
[7]: https://sequelize.org/master/manual/model-basics.html
[8]: http://www.haproxy.org/
[9]: https://en.wikipedia.org/wiki/Single_point_of_failure
[10]: https://sequelize.org/master/manual/read-replication.html
