# Build stage
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

# Copy csproj and restore dependencies
COPY ["OverviewDashboard/OverviewDashboard.csproj", "OverviewDashboard/"]
RUN dotnet restore "OverviewDashboard/OverviewDashboard.csproj"

# Copy everything else and build
COPY . .
WORKDIR "/src/OverviewDashboard"
RUN dotnet build "OverviewDashboard.csproj" -c Release -o /app/build

# Publish stage
FROM build AS publish
RUN dotnet publish "OverviewDashboard.csproj" -c Release -o /app/publish \
    /p:SelfContained=false \
    /p:PublishSingleFile=false

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS final
WORKDIR /app
EXPOSE 8080
EXPOSE 8081

# Copy published app
COPY --from=publish /app/publish .

# Create Database directory for SQLite
RUN mkdir -p /app/Database

# Copy database if it exists (optional - you might want to use a volume instead)
# COPY Database/ /app/Database/

ENTRYPOINT ["dotnet", "OverviewDashboard.dll"]
