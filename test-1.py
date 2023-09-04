import json
import os


with open('1.json', 'r') as scao_file1:
    # Read the first line
    rds_hostname = scao_file1.readline().strip()

with open('2.json', 'r') as scao_file2:
    # Read the first line
    lb_dns_address = scao_file2.readline().strip()

# Access the value of an environment variable
env_rds_address = os.environ.get('MY_VAR')
env_lb_address = os.environ.get('MY_LBDNS')

# Read the first JSON file
with open('splunk_config.json', 'r') as first_file:
    first_data = json.load(first_file)
    new_password = first_data.get('splunk_search_password')
    new_password1 = first_data.get('splunk_delete_password')
    new_token = first_data.get('splunk_event_collector_token')

# Read the second JSON file
with open('response.json', 'r') as second_file:
    second_data = json.load(second_file)
    second_data['splunk_search_password'] = new_password
    second_data['splunk_delete_password'] = new_password1
    second_data['splunk_event_collector_token'] = new_token
    second_data['external_db_location'] = rds_hostname
    second_data['haproxy_server'] = lb_dns_address



# Write the updated data back to the second JSON file
with open('response.json', 'w') as second_file:
    json.dump(second_data, second_file, indent=4)