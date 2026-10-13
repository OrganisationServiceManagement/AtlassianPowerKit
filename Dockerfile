FROM mcr.microsoft.com/powershell:latest

WORKDIR /app
ENV OSM_HOME=/mnt/osm \
    OSM_INSTALL=/app

RUN ["pwsh", "-NoLogo", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; Install-Module -Name PowerShellGet,Microsoft.PowerShell.SecretManagement,Microsoft.PowerShell.SecretStore -Repository PSGallery -Scope AllUsers -Force"]

COPY . /app

ENTRYPOINT ["pwsh", "-NoLogo", "-NoProfile"]
CMD ["-Command", "$ErrorActionPreference = 'Stop'; Import-Module /app/AtlassianPowerKit.psd1 -Force; AtlassianPowerKit"]
