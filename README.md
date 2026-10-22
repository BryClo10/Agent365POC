# Agent365POC
"""
Install tools
These are the four programs the runbook uses. You do not need to open any of them yourself. The commands in this runbook use them for you.
Program	What it is for
"""
Python 3.11	Runs the scripts that deploy, test and check the agent
Google Cloud CLI	Talks to your Google Cloud project
.NET SDK	Needed by the Agent 365 tool
Azure CLI	Talks to Microsoft Entra for one of the tests
"""

"""
Open PowerShell from the Start menu and paste this box. It downloads and installs all four, which takes about 10 minutes. If Windows asks whether to allow changes, select Yes. The first line lets PowerShell run the Google Cloud tool.
"""
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
winget install -e --id Python.Python.3.11 --accept-source-agreements --accept-package-agreements
winget install -e --id Google.CloudSDK --accept-source-agreements --accept-package-agreements
winget install -e --id Microsoft.DotNet.SDK.8 --accept-source-agreements --accept-package-agreements
winget install -e --id Microsoft.AzureCLI --accept-source-agreements --accept-package-agreements

"""
Close PowerShell, open it again from the Start menu, and paste this to check that everything installed. Each line should print a version number.
"""
py -3.11 --version
gcloud --version
dotnet --version
az version

