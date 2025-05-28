# Use the official PowerShell image as the base image
FROM mcr.microsoft.com/powershell:latest

# Set the working directory
WORKDIR /mnt/osm

# Install Git and required PowerShell modules
#RUN apt-get update && \
#    apt-get install -y git && \
#    apt-get clean && \
#    rm -rf /var/lib/apt/lists/* && \
#    mkdir -p /mnt/osm && \
#    chmod 755 -R ./*
RUN pwd && \
    chmod 755 -R /mnt
RUN pwsh -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted" && \
    pwsh -Command "Install-Module -Name PowerShellGet -Force" && \
    pwsh -Command "Install-Module -Name Microsoft.PowerShell.SecretManagement,Microsoft.PowerShell.SecretStore -Force"

# Set the entry point
ENTRYPOINT ["pwsh"]

