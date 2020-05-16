# Tyk Demo

This repo provides an example installation of Tyk. It uses Docker Compose to provide a quick, simple deployment, where you can choose what features to include.

The concept is that there is a **standard deployment** of Tyk, which gives you the usual Tyk components: Gateway, Dashboard, Pump, plus the databases Redis and MongoDB. This standard deployment can be extended by including additional **feature deployments** as needed. The feature deployments cover particular scenarios for Tyk, such as:

* Single sign on
* TLS
* Analytics export
* Tracking
* CI/CD
* 2nd Tyk Environment
* Instrumentation

Each feature deployment has its own directory, with the necessary files to deploy the feature and a readme to describe the feature.

There is a focus on simplicity. Docker Compose is used to provision the containers, and bootstrap scripts are used to initialise the environment so that it is ready to use straight away - applying configuration and populating databases.

# Repository Structure

* `deployments/*`: Contains all the deployments available as sub-directories
* `tyk_demo.postman_collection.json`: A Postman collection of requests which correspond to APIs available in the deployment
* `scripts/*.sh`: Some useful commands encapsulated in scripts
* `up.sh`: Brings up the deployment
* `down.sh`: Takes down the deployment

## Deployments

The deployment directories (`deployments/*`) contain the various deployments which can be made with this repo. The **base deployment** is in the `tyk` directory, which is a standard Tyk deployment. The other directories are **feature deployments**, which extend the **base deployment** functionality. 

All of the directories contain `docker-compose.yml`, `bootstrap.sh` and `README.md` files specific to the deployment. They may also contain directories called `data` or `volumes`, which hold the data necessary during bootstrapping or providing as mapped volumes into the container.

# Getting Started

## Step 1: Install dependencies

### JQ

The bootstrap script uses JQ for extracting data from JSON object, it can be installed as follows:

```
brew install jq
```

## Step 2: Add Docker Environment variables

The `docker-compose.yml` file uses a Docker environment variable to set the dashboard licence. To set this, create a file called `.env` in the root directory of the repo, then set the content of the file as follows, replacing `<YOUR_LICENCE>` with your Dashboard licence:

```
DASHBOARD_LICENCE=<YOUR_LICENCE>
```

In addition to this, some features require entries in the `.env` file. These are set automatically by the `bootstrap.sh` files, depending on the deployment.

## Step 3: Make the scripts executable

There are two scripts which can be used to bring up and tear down the deployment: `up.sh` and `down.sh`.

Make these scripts executable:

```
chmod +x up.sh down.sh
```

## Step 4: Bring the deployment up

To bootstrap the system we will run the `up.sh` script, which will run the necessary `docker-compose` and `bootstrap` commands to start the containers and bootstrap the system. 

```
./up.sh
```

This will bring up the standard Tyk deployment, after which you can log into the Dashboard and start using Tyk.

### Deploying a feature

If you want to deploy features, run the `up.sh` command, passing a parameter of the directory name of the feature to deploy. For example, to deploy both the base `tyk` deployment and the `analytics` feature:

```
./up.sh analytics
```

The feature names are the directory names from the `deployments` directory.

### Deploying multiple features at the same time

Multiple features can be deployed at the same time by providing multiple feature parameters. For example, to deploy `analytics` and `instrumentation`:

```
./up.sh analytics instrumentation
```

### Bootstrap logging

The bootstrap scripts provide feedback on progress in the `bootstrap.log` file.

## Step 5: Log into the Dashboard

The bootstrap process provides credentials and other useful information in the terminal output. Check this output for the Dashboard credentials.

When you log into the Dashboard, you will find the imported APIs and Policies are now available.

## Step 6: Import API requests into Postman

There is a Postman collection provided which compliments the imported API definitions and Policies. This lets you demonstrate Tyk features and functionality.

Import the `tyk_demo.postman_collection.json` into your [Postman](https://postman.com) to start making requests.

# Resetting

If you want to reset your environment then you need to remove the volumes associated with the container as well as the containers themselves. The `down.sh` script can do this for you.

To bring down the containers and delete associated volumes:

```
./down.sh
```

If you used deployment parameters when running the `up.sh` script, you should also include them when taking the system down. For example, to bring down the standard Tyk and `analytic` deployments:

```
./down.sh analytics
```

# Redeploying

The `up.sh` script is not intended to be run consecutively without running `down.sh` in between. The reason for this is that the `up.sh` script assumes that the system will not contain any data, so it attempts to bootstrap the system by creating data. This means that running the script repeatedly will result in duplicate data.

# Working with APIs and Policies

There are two scenarios for working with this data:

1. You have made changes and want to commit them so that others can get them
2. You want to get the changes other people have made

## Scenario 1: Committing changes

If you have changed APIs and Policies in your Dashboard, and want to commit these so other people can use them, use the `export.sh` script.

Run from the repo root directory, as so:

```
./scripts/export.sh
```

This will update the `apis.json` and `policies.json` files in the `deployments/tyk/data/tyk-dashboard` directory. You can then commit these files into the repo.

When adding functionality to this repo, please also add requests to the Postman collection to demonstrate the functionality, and add tests to the requests to validate them. Once the requests and tests are added, export the collection and overwrite the `tyk_demo.postman_collection.json` file, which can then be commited too.

## Scenario 2: Synchronising updates

If you want to get the changes other people have made, first pull from the repo, then use the `import.sh` script.

Run from the repo root directory, as so:

```
./scripts/import.sh
```

## Why not use Tyk Sync?

The Tyk Sync binary is not always kept up-to-date with the latest changes in API and Policy object, which unfortunately means that the data it exports may be missing information. This also means that when this data is imported into the system, that the objects created will also be missing this data.

So, until the Tyk Sync project is updated and released in-line with the Tyk Dashboard project, it is safer to manually handle data import and export directly with the Dashboard API.
