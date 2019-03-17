FROM vmware/powerclicore
ENV TERM linux
RUN tdnf install -y xorriso
SHELL [ "pwsh", "-command" ]
RUN Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Scope AllUsers -Confirm:$false
COPY DeployVM.ps1 /root
COPY user-data-template /root
COPY os/bionic-server-cloudimg-amd64/ /root