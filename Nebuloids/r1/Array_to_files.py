import json
import os

# Specify the input JSON file containing the array of objects
input_file = './AllData.json'

# Create a directory to store individual JSON files (if it doesn't exist)
output_directory = './uri'
os.makedirs(output_directory, exist_ok=True)

# Read the input JSON file
with open(input_file, 'r') as f:
    data = json.load(f)

# Iterate through each object in the array
for index, obj in enumerate(data):
    # Create a filename for the individual JSON file (e.g., object_1.json, object_2.json, etc.)
    output_file = os.path.join(output_directory, f'{index + 1}')

    # Write the current object to the individual JSON file
    with open(output_file, 'w') as f:
        json.dump(obj, f, indent=4)

print(f'Individual JSON files created in the "{output_directory}" directory.')
