# ==========================================
# STAGE 1: The Compilation & Building Phase
# ==========================================
# We fetch a heavy Docker image directly from Microsoft that contains the full .NET 10.0 SDK.
# This gives the container the 'dotnet build' and 'dotnet publish' tools it needs.
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build-env

# Create and move into an internal folder inside the container called '/app'
WORKDIR /app

# Copy your C# project file from your computer into the container's current directory
COPY *.csproj ./

# Run a package restore to download all NuGet packages (like Entity Framework and Npgsql)
RUN dotnet restore

# Copy every other source code file from your local Backend folder into the container
COPY . ./

# Compile your code into a highly optimized, production release version.
# Output the compiled executable files into an internal folder called '/app/out'
RUN dotnet publish -c Release -o out


# ==========================================
# STAGE 2: The Final Lightweight Runtime Phase
# ==========================================
# We throw away the heavy SDK container used above. 
# Instead, we pull a tiny, stripped-down image that ONLY contains the minimal .NET 10 runtime environment.
FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app

# Copy the optimized, compiled application files from STAGE 1 (/app/out) into this clean container
COPY --from=build-env /app/out .

# Expose internal network port 5212 so external traffic can access the API gateway
EXPOSE 5212
ENV ASPNETCORE_URLS=http://+:5212

# Tell the container exactly what command to execute when it boots up.
# Note: If your project file is named something else like "MyGame.csproj", change "Backend.dll" to "MyGame.dll"
ENTRYPOINT ["dotnet", "Backend.dll"]
