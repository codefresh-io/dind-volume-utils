# What is this script doing?
This migration script will run the migration logic on each of the cluster nodes and add the `codefresh.io/assignedNode` annotation to the `PersistentVolume` entities that are of type local volume. After running this migration script the codefresh volume provisioner would be able to cleanup the local-volumes from the nodes when the cleanup job decides their `PersistentVolume` should be deleted.

# How to run?
To run the migration script you need to have `kubectl` binary installed. Make sure the current kubernetes context is the cluster you want and run the script like this:
```
NAMESPACE=<codefresh-ns> ./run.sh
```
The namespace should be the namespace of your codefresh runtime.
