#!/bin/bash

az extension list-available | jq -r '.[] | select(.name=="aks-preview") | .version'
