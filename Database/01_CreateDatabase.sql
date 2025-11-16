-- =============================================
-- IT Infrastructure Dashboard Database Schema
-- =============================================

USE master;
GO

-- Create Database
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'ITDashboard')
BEGIN
    CREATE DATABASE ITDashboard;
    PRINT 'Database ITDashboard created successfully.';
END
ELSE
BEGIN
    PRINT 'Database ITDashboard already exists.';
END
GO

USE ITDashboard;
GO

-- =============================================
-- Table: Systems
-- =============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Systems]') AND type in (N'U'))
BEGIN
    CREATE TABLE [dbo].[Systems] (
        [Id] INT IDENTITY(1,1) PRIMARY KEY,
        [SystemId] NVARCHAR(50) NOT NULL UNIQUE,
        [Name] NVARCHAR(200) NOT NULL,
        [Description] NVARCHAR(500) NULL,
        [IsActive] BIT NOT NULL DEFAULT 1,
        [CreatedDate] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        [ModifiedDate] DATETIME2 NOT NULL DEFAULT GETUTCDATE()
    );
    PRINT 'Table Systems created successfully.';
END
GO

-- =============================================
-- Table: Projects
-- =============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Projects]') AND type in (N'U'))
BEGIN
    CREATE TABLE [dbo].[Projects] (
        [Id] INT IDENTITY(1,1) PRIMARY KEY,
        [ProjectId] NVARCHAR(50) NOT NULL UNIQUE,
        [SystemId] INT NOT NULL,
        [Name] NVARCHAR(200) NOT NULL,
        [Description] NVARCHAR(500) NULL,
        [IsActive] BIT NOT NULL DEFAULT 1,
        [CreatedDate] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        [ModifiedDate] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CONSTRAINT FK_Projects_Systems FOREIGN KEY ([SystemId]) 
            REFERENCES [dbo].[Systems]([Id]) ON DELETE CASCADE
    );
    PRINT 'Table Projects created successfully.';
END
GO

-- =============================================
-- Table: Components
-- =============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Components]') AND type in (N'U'))
BEGIN
    CREATE TABLE [dbo].[Components] (
        [Id] INT IDENTITY(1,1) PRIMARY KEY,
        [ComponentId] NVARCHAR(50) NOT NULL UNIQUE,
        [ProjectId] INT NOT NULL,
        [Name] NVARCHAR(200) NOT NULL,
        [Description] NVARCHAR(500) NULL,
        [ComponentType] NVARCHAR(50) NOT NULL, -- CPU, Memory, Disk, Service, etc.
        [IsActive] BIT NOT NULL DEFAULT 1,
        [CreatedDate] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        [ModifiedDate] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CONSTRAINT FK_Components_Projects FOREIGN KEY ([ProjectId]) 
            REFERENCES [dbo].[Projects]([Id]) ON DELETE CASCADE
    );
    PRINT 'Table Components created successfully.';
END
GO

-- =============================================
-- Table: ComponentMetrics
-- =============================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ComponentMetrics]') AND type in (N'U'))
BEGIN
    CREATE TABLE [dbo].[ComponentMetrics] (
        [Id] BIGINT IDENTITY(1,1) PRIMARY KEY,
        [ComponentId] INT NOT NULL,
        [Severity] NVARCHAR(20) NOT NULL, -- ok, warning, error, info
        [Value] NVARCHAR(100) NOT NULL,
        [Metric] NVARCHAR(50) NOT NULL, -- %, GB, count, etc.
        [RawValue] DECIMAL(18,4) NULL, -- Numeric value for queries/sorting
        [Description] NVARCHAR(1000) NULL,
        [CollectedDate] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CONSTRAINT FK_ComponentMetrics_Components FOREIGN KEY ([ComponentId]) 
            REFERENCES [dbo].[Components]([Id]) ON DELETE CASCADE,