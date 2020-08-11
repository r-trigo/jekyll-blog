---
layout: post
title: Connecting Sequelize to a PostgreSQL cluster
---
:large_blue_diamond: :elephant: :sheep:

## Prologue
In the [previous post][1] we showed how to automate a PostgreSQL fault-tolerant cluster with Vagrant and Ansible.

This kind of setup makes our database cluster resilient to server failure and keeps the data available with no need for human interaction. What about the apps using this database? Are they fault-tolerant too? ORMs like Sequelize have [read replication][2] features, which allows you to define your primary and standby nodes in the database connection. But what happens if your primary node, which is responsible for write operations, is offline and your app needs to continue saving data on your database?

One way to solve this is adding an extra layer to the system - a load balancing layer - using PostgreSQL 3rd party tools like [pgbouncer][3] or [Pgpool-II][4] or even a properly configured [HAproxy][5] instance. Besides the complexity brought by this method, you could also be introducing an undesired [single point of failure][6].

Another way is using a floating IP address/virtual IP address to assign to the current primary database node, so the application knows which node it must connect to when performing write operations even if another node takes up primary role.

## Objectives
- connecting a **NodeJS** application with **Sequelize** to a **PostgreSQL** cluster in order to write from primary and read from standby nodes;
- create and assign a **Digital Ocean Floating IP** (aka FLIP) to our current primary database node;
- make **repmgr** interact with **Digital Ocean CLI** to reassign FLIP to new primary node on promotions;
- keep this switchover transparent to the **NodeJS** application, so the whole system works without human help.

## Pre-requisites
- **Digital Ocean** account and API token ([create an account using my referral to get free credits][7])
- **PostgreSQL** cluster with **repmgr** on **Digital Ocean** (you can grab the **Ansible** playbook in this [tutorial][1] to configure it or just use a cluster with streaming replication and simulate failure + manual promotion)
- [NodeJS][8] and [npm][9] installed (I'm using **NodeJS** v12 with **npm** v6)
- a **PostgreSQL** user with password authentication which accepts remote connections from your application host (I'll be using `postgres`:`123456`)

## Setup your cluster
### Create your droplets
![img](img)
Create 3 droplets with preferably Ubuntu 20.04 operating system:
- pg1 (primary)
- pg2 (standby)
- pg3 (witness)
To make configurations run smoother, add your public SSH key when creating the droplets. You can also use the key pair I provided on [Github][98] for testing purposes.
>If you'd like to use only 2 droplets, you can ignore the 3rd node as it will be an PostgreSQL witness

![img2](img2)

### Assign a floating IP to your
![img3](img3)
Create a floating IP address and assign it to your primary node (pg1).

### Configure PostgreSQL with repmgr
As previously stated, you can use the [Ansible playbook from the last post][1] to speed up the configuration. Download it from [GitHub][99] and insert your gateway and droplets IPv4 addresses on `group_vars/all.yaml`:

```yaml
client_ip: "<your_gateway_public_ipv4>"
node1_ip: "<droplet_pg1_ipv4>"
node2_ip: "<droplet_pg2_ipv4>"
node3_ip: "<droplet_pg3_ipv4>"
pg_version: "12"
```
*Note: I am assuming you will run your app locally on your computer and it will connect to your droplets through your network gateway*
If you don't know your current public gateway address, you can run:
```bash
curl ifconfig.io -4
```

Create an **Ansible** inventory file and add the playbook `host_vars` for each host. I named mine `digitalocean`:
```
[all]
pg1 ansible_host=<droplet_pg1_ipv4> connection_host="<droplet_pg1_ipv4>" node_id=1 role="primary"
pg2 ansible_host=<droplet_pg2_ipv4> connection_host="<droplet_pg2_ipv4>" node_id=2 role="standby"
pg3 ansible_host=<droplet_pg3_ipv4> connection_host="<droplet_pg3_ipv4>" node_id=3 role="witness"
```

Add the droplets to the list of SSH known hosts accessing them and exiting the session:
```bash
ssh root@<droplet_pg1_ipv4>
exit
ssh root@<droplet_pg2_ipv4>
exit
ssh root@<droplet_pg3_ipv4>
exit
```

Now run the playbook with:
```bash
ansible-playbook playbook.yaml -e "ansible_ssh_user=root"
```
`-e "ansible_ssh_user=root` passes an environment variable to make **Ansible** connect as `root` user

### NodeJS application
Let's write a simple app, which manipulates a `countries` table. Keep in mind [pluralization in Sequelize][10] for Javascript objects and default database table names. Set it up with:

```bash
mkdir sequelize-postgresql-cluster
cd sequelize-postgresql-cluster
npm init -y
npm install pg sequelize
```

Now edit `index.js` with the following:

```js
const { Sequelize } = require('sequelize');

const primary_ipv4 = '<droplet_pg1_ipv4>'
const standby_ipv4 = '<droplet_pg2_ipv4>'

// new Sequelize(database, username, password)
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

Above created a **Sequelize** connection object named `sequelize` and configured our servers addresses in it. The `connect` function tests the connection to the database. Make sure your app can connect to it correctly before proceeding.

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

`Country` is our **Sequelize** model, a Javascript object which represents the database table.
`create_table()`, `insertCountry()` and `findAllCountries()` functions are self-explanatory. They will be called through `run()` function.
Run your app with:
```bash
node index.js
```
This will create the `countries` table on the **PostgreSQL** database, insert a row in it and read table data. Because of streaming replication, this data will automatically be replicated into the standby node.

### **(Optional)** Current status primary failure test
*If you perform this step you'll need to revert the PostgreSQL promotion and go back to cluster inital state. There are instructions for this in the [mentioned tutorial][1].*

Turn off your `pg1` droplet (can be done through Digital Ocean interface). Due to `repmgrd` configuration, the standby node (`pg2`) promote itself to prymary role, so your database cluster keeps working. This promotion will make your app still able to read data, but not write. Proceed reverting the cluster to the previous status, with `pg1` being the primary node.

## Use a floating IP
### Add the floating IP address to your app database connection object
To take advantage of floating IP, insert it into a variable and edit the write object of `sequelize` object.

```js
// insert this line
const floating_ipv4 = 'your_floating_ip_goes_here'
(...)
// edit this line
write: { host: floating_ipv4 }
```

## Digital Ocean CLI configuration
As we will `pg2` node to interact with Digital Ocean and reassign the floating IP to its IPv4 address, we must configure `doctl` in this server. Below is a script which performs this configuration and reassigns the floating IP to the `pg2`.

TODO: script

```bash
mkdir /opt/scripts/
vim /opt/scripts/reassign-floating-ip.sh
chmod a+x /opt/scripts/reassign-floating-ip.sh
```

### Add the script to repmgr promote command
Now edit `pg2` `repmgr.conf` file to invoke our `reassign-floating-ip.sh` script on promotion time.
```
promote_command = 'repmgr standby promote -f /etc/repmgr.conf && /opt/scripts/reassign-floating-ip.sh'
```
Run `service postgresql restart && repmgrd` to apply changes.

## Final status primary failure test
Unlike before, when you turn off `pg1`, `pg2` not only promotes itself but also takes over the floating IP, which the app is currently using to perform write operations. As `pg2` was already in the `sequelize` variable `read` array, it is now capable and the sole responsible for data reads and writes. Wait a minute for the promotion to happen and test app again:

```bash
node index.js
```

## Conclusion
Picture yourself in a boat on a river (yes, it's a Beatles reference). If both your oars break loose and only one can be fixed on the spot, the boat motion will become defective and it will be hard to continue the trip.

In this specific case, before having a floating IP your app would recover data read capability through database fault-tolerance behaviour, but your app wouldn't be able to perform writes in this condition. Now that your app follows the database primary on automatic promotions, you can heal the cluster and revert it to initial state in planned conditions and with no rush, as app features are safeguarded.

## Final notes
- This strategy also works with other cloud providers who support floating IP.
- If you use a SSH private key which is shared in GitHub, for example, your cluster can get hacked.
- If using in production secure the API token variable in Digital Ocean CLI configuration script and be careful with reassigning script permissions.
- Read [my last post][1] if you haven't as it will help following this tutorial.
- You can find the source code in this post [on Github][99].
- Create your Digital Ocean account [here][7] to earn free credits.

[1]: https://blog.jscrambler.com/how-to-automate-postgresql-and-repmgr-on-vagrant/
[2]: https://sequelize.org/master/manual/read-replication.html
[3]: http://www.pgbouncer.org/
[4]: https://wiki.postgresql.org/wiki/Pgpool-II
[5]: http://www.haproxy.org/
[6]: https://en.wikipedia.org/wiki/Single_point_of_failure
[7]: https://m.do.co/c/00ac35d4c268
[8]: https://nodejs.org/en/download/
[9]: https://www.npmjs.com/
[10]: https://sequelize.org/master/manual/model-basics.html

[98]: https://github.com/r-trigo/postgres-repmgr-vagrant/tree/master/provisioning/roles/ssh/files/keys
[99]: https://github.com/r-trigo/postgres-repmgr-vagrant
