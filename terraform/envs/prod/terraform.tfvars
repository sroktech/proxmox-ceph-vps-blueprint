pve_endpoint         = "https://pve-01.dc1.example.net:8006/"
primary_node         = "pve-01"
cluster_nodes        = ["pve-01", "pve-02", "pve-03"]
vxlan_underlay_peers = ["10.10.40.11", "10.10.40.12", "10.10.40.13"]
sdn_exit_nodes       = ["pve-01", "pve-02"]

# pve_api_token is deliberately absent. Supply it as:
#   TF_VAR_pve_api_token=$(sops -d --extract '["pve_api_token"]' secrets.sops.yaml)
