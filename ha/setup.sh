#!/bin/bash

find . -type f -exec sed -i 's/ip1/0.0.0.0/g' {} +
find . -type f -exec sed -i 's/ip2/0.0.0.0/g' {} +
find . -type f -exec sed -i 's/your-domain.com/real-domain.com/g' {} +
