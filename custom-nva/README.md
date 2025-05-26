### To see logs of last apply_nva_config run on NVA VM:

sudo cat /var/lib/waagent/run-command-handler/download/apply-nva-configuration/0/stdout
sudo cat /var/lib/waagent/run-command-handler/download/apply-nva-configuration/0/stderr

### Useful tcpdump commands

sudo tcpdump -i eth1 -n 'icmp and host 10.100.1.4 and host 10.100.2.4'
sudo tcpdump -i eth1 -n 'host 10.100.1.4 and host 8.8.8.8 and icmp'
