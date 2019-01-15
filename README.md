# Dind Volume Utils

Useful prom queries

# dind space usage per account

(docker_volume_kb_usage > 0.3) + on (dind_name)  group_left(io.codefresh.accountName, runtime_env) label_replace(dind_pvc_status{dind_pod_name != "<no value>"} * 0, "dind_name", "$1", "dind_pod_name", "(.*)") 


(docker_volume_kb_usage > 0.9 ) + on (dind_name)  group_left(io.codefresh.accountName, runtime_env, backend_volume_id, volume_name) label_replace(dind_pvc_volume_mount_count{dind_pod_name != "<no value>"} * 0, "dind_name", "$1", "dind_pod_name", "(.*)") 

# dind space usage per build
max_over_time(docker_volume_kb_usage{dind_name="pvc-dind-5b190f66aa335e00016071d3"}[1d])

