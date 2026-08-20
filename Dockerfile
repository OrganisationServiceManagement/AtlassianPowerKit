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
COPY . /mnt/osm
RUN pwd && \
    chmod 755 -R /mnt
RUN pwsh -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted" && \
    pwsh -Command "Install-Module -Name PowerShellGet -Force" && \
    pwsh -Command "Install-Module -Name Microsoft.PowerShell.SecretManagement,Microsoft.PowerShell.SecretStore -Force" && \
    pwsh -Command "Import-Module Microsoft.PowerShell.SecretManagement,Microsoft.PowerShell.SecretStore -Force" && \
    pwsh -Command "Install-Module AtlassianPowerKit.psd1 -Force" && \
    pwsh -Command "Import-Module .\AtlassianPowerKit.psd1 -Force" && \
    pwsh -Command "Write-Host 'Importing psd1s in /mnt/osm'" && \
    pwsh -Command "Get-ChildItem -Path /mnt/osm -Filter *.psd1 -Recurse | ForEach-Object { Write-Host 'Importing module from:' $_.FullName; Import-Module $_.FullName -Force }"

# Set the entry point
ENTRYPOINT ["AtlassianPowerKit"]
