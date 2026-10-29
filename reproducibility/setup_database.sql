-- Run only against a new, empty database selected in SSMS.
-- Review the CSV import directory in the second section before running.
-- SQL Server: run in a new database. Non-destructive: existing tables are skipped.
-- CSV UTF-8 BOM; blank fields -> NULL; map columns to the existing tables.
SET NOCOUNT ON;
GO
IF OBJECT_ID(N'dbo.zone_table', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[zone_table] (
    [zone_id] BIGINT NOT NULL,
    [zone_name] NVARCHAR(200) NOT NULL,
    [center_latitude] DECIMAL(18,6) NOT NULL,
    [center_longitude] DECIMAL(18,6) NOT NULL,
    [zone_type] NVARCHAR(200) NOT NULL,
    CONSTRAINT [PK_zone_table] PRIMARY KEY ([zone_id])
);
END;
GO
IF OBJECT_ID(N'dbo.service_table', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[service_table] (
    [service_type] NVARCHAR(200) NOT NULL,
    [service_name] NVARCHAR(200) NOT NULL,
    [description] NVARCHAR(200) NOT NULL,
    CONSTRAINT [PK_service_table] PRIMARY KEY ([service_type])
);
END;
GO
IF OBJECT_ID(N'dbo.date_table', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[date_table] (
    [date] DATE NOT NULL,
    [year] BIGINT NOT NULL,
    [month] BIGINT NOT NULL,
    [month_start] DATE NOT NULL,
    [day_of_week_no] BIGINT NOT NULL,
    [day_of_week_name] NVARCHAR(200) NOT NULL,
    [is_weekend] BIGINT NOT NULL,
    CONSTRAINT [PK_date_table] PRIMARY KEY ([date])
);
END;
GO
IF OBJECT_ID(N'dbo.user_table', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[user_table] (
    [user_id] BIGINT NOT NULL,
    [user_name] NVARCHAR(200) NOT NULL,
    [phone_number] VARCHAR(10) NOT NULL,
    [registered_at] DATETIME2(0) NOT NULL,
    [home_zone_id] BIGINT NOT NULL,
    [acquisition_channel] NVARCHAR(200) NOT NULL,
    CONSTRAINT [PK_user_table] PRIMARY KEY ([user_id])
);
END;
GO
IF OBJECT_ID(N'dbo.driver_table', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[driver_table] (
    [driver_id] BIGINT NOT NULL,
    [driver_name] NVARCHAR(200) NOT NULL,
    [phone_number] VARCHAR(10) NOT NULL,
    [service_type] NVARCHAR(200) NOT NULL,
    [joined_at] DATETIME2(0) NOT NULL,
    [home_zone_id] BIGINT NOT NULL,
    [status_as_of] NVARCHAR(200) NOT NULL,
    [status_as_of_at] DATETIME2(0) NOT NULL,
    CONSTRAINT [PK_driver_table] PRIMARY KEY ([driver_id])
);
END;
GO
IF OBJECT_ID(N'dbo.weather_hourly_table', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[weather_hourly_table] (
    [weather_id] BIGINT NOT NULL,
    [zone_id] BIGINT NOT NULL,
    [hour_start_at] DATETIME2(0) NOT NULL,
    [rainfall_mm] DECIMAL(18,6) NOT NULL,
    [is_raining] BIGINT NOT NULL,
    CONSTRAINT [PK_weather_hourly_table] PRIMARY KEY ([weather_id])
);
END;
GO
IF OBJECT_ID(N'dbo.driver_session_table', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[driver_session_table] (
    [session_id] BIGINT NOT NULL,
    [driver_id] BIGINT NOT NULL,
    [service_type] NVARCHAR(200) NOT NULL,
    [online_at] DATETIME2(0) NOT NULL,
    [offline_at] DATETIME2(0) NULL,
    [observation_end_at] DATETIME2(0) NOT NULL,
    [start_zone_id] BIGINT NOT NULL,
    CONSTRAINT [PK_driver_session_table] PRIMARY KEY ([session_id])
);
END;
GO
IF OBJECT_ID(N'dbo.trip_table', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[trip_table] (
    [trip_id] VARCHAR(36) NOT NULL,
    [user_id] BIGINT NOT NULL,
    [driver_id] BIGINT NULL,
    [created_at] DATETIME2(0) NOT NULL,
    [accepted_at] DATETIME2(0) NULL,
    [arrived_at] DATETIME2(0) NULL,
    [pickup_at] DATETIME2(0) NULL,
    [finished_at] DATETIME2(0) NULL,
    [cancelled_at] DATETIME2(0) NULL,
    [expired_at] DATETIME2(0) NULL,
    [status] BIGINT NOT NULL,
    [cancelled_by] NVARCHAR(200) NULL,
    [cancel_reason] NVARCHAR(200) NULL,
    [service_type] NVARCHAR(200) NOT NULL,
    [pickup_zone_id] BIGINT NOT NULL,
    [dropoff_zone_id] BIGINT NOT NULL,
    [pickup_latitude] DECIMAL(18,6) NOT NULL,
    [pickup_longitude] DECIMAL(18,6) NOT NULL,
    [dropoff_latitude] DECIMAL(18,6) NOT NULL,
    [dropoff_longitude] DECIMAL(18,6) NOT NULL,
    [estimated_trip_distance_km] DECIMAL(18,6) NOT NULL,
    [actual_trip_distance_km] DECIMAL(18,6) NULL,
    [quoted_trip_duration_min] DECIMAL(18,6) NOT NULL,
    [quoted_pickup_eta_min] DECIMAL(18,6) NULL,
    [weather_id] BIGINT NOT NULL,
    [request_group_id] VARCHAR(36) NOT NULL,
    [parent_trip_id] VARCHAR(36) NULL,
    [driver_id_refused] VARCHAR(2000) NOT NULL,
    CONSTRAINT [PK_trip_table] PRIMARY KEY ([trip_id])
);
END;
GO
IF OBJECT_ID(N'dbo.dispatch_offer_table', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[dispatch_offer_table] (
    [offer_id] BIGINT NOT NULL,
    [trip_id] VARCHAR(36) NOT NULL,
    [driver_id] BIGINT NOT NULL,
    [session_id] BIGINT NOT NULL,
    [attempt_no] BIGINT NOT NULL,
    [service_type] NVARCHAR(200) NOT NULL,
    [pickup_zone_id] BIGINT NOT NULL,
    [sent_at] DATETIME2(0) NOT NULL,
    [response_at] DATETIME2(0) NULL,
    [resolved_at] DATETIME2(0) NULL,
    [outcome] NVARCHAR(200) NOT NULL,
    [estimated_pickup_distance_km] DECIMAL(18,6) NOT NULL,
    [estimated_pickup_eta_min] DECIMAL(18,6) NOT NULL,
    [eligible_driver_count_at_send] BIGINT NOT NULL,
    CONSTRAINT [PK_dispatch_offer_table] PRIMARY KEY ([offer_id])
);
END;
GO
IF OBJECT_ID(N'dbo.driver_state_interval_table', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[driver_state_interval_table] (
    [state_interval_id] BIGINT NOT NULL,
    [session_id] BIGINT NOT NULL,
    [driver_id] BIGINT NOT NULL,
    [service_type] NVARCHAR(200) NOT NULL,
    [zone_id] BIGINT NOT NULL,
    [state] NVARCHAR(200) NOT NULL,
    [started_at] DATETIME2(0) NOT NULL,
    [ended_at] DATETIME2(0) NOT NULL,
    CONSTRAINT [PK_driver_state_interval_table] PRIMARY KEY ([state_interval_id])
);
END;
GO
IF OBJECT_ID(N'dbo.supply_15min_table', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[supply_15min_table] (
    [interval_start_at] DATETIME2(0) NOT NULL,
    [interval_end_at] DATETIME2(0) NOT NULL,
    [zone_id] BIGINT NOT NULL,
    [service_type] NVARCHAR(200) NOT NULL,
    [online_driver_minutes] DECIMAL(18,6) NOT NULL,
    [available_driver_minutes] DECIMAL(18,6) NOT NULL,
    [offer_pending_driver_minutes] DECIMAL(18,6) NOT NULL,
    [to_pickup_driver_minutes] DECIMAL(18,6) NOT NULL,
    [waiting_pickup_driver_minutes] DECIMAL(18,6) NOT NULL,
    [on_trip_driver_minutes] DECIMAL(18,6) NOT NULL,
    [occupied_driver_minutes] DECIMAL(18,6) NOT NULL,
    CONSTRAINT [PK_supply_15min_table] PRIMARY KEY ([interval_start_at],[zone_id],[service_type])
);
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.trip_table') AND name=N'IX_trip_table_user_id_created_at')
CREATE INDEX [IX_trip_table_user_id_created_at] ON [dbo].[trip_table] ([user_id],[created_at]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.trip_table') AND name=N'IX_trip_table_driver_id_accepted_at')
CREATE INDEX [IX_trip_table_driver_id_accepted_at] ON [dbo].[trip_table] ([driver_id],[accepted_at]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.trip_table') AND name=N'IX_trip_table_created_at_service_type_pickup_zone_id')
CREATE INDEX [IX_trip_table_created_at_service_type_pickup_zone_id] ON [dbo].[trip_table] ([created_at],[service_type],[pickup_zone_id]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.dispatch_offer_table') AND name=N'IX_dispatch_offer_table_trip_id_attempt_no')
CREATE INDEX [IX_dispatch_offer_table_trip_id_attempt_no] ON [dbo].[dispatch_offer_table] ([trip_id],[attempt_no]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.dispatch_offer_table') AND name=N'IX_dispatch_offer_table_driver_id_sent_at')
CREATE INDEX [IX_dispatch_offer_table_driver_id_sent_at] ON [dbo].[dispatch_offer_table] ([driver_id],[sent_at]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.driver_state_interval_table') AND name=N'IX_driver_state_interval_table_driver_id_started_at')
CREATE INDEX [IX_driver_state_interval_table_driver_id_started_at] ON [dbo].[driver_state_interval_table] ([driver_id],[started_at]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.driver_session_table') AND name=N'IX_driver_session_table_driver_id_online_at')
CREATE INDEX [IX_driver_session_table_driver_id_online_at] ON [dbo].[driver_session_table] ([driver_id],[online_at]);
GO

GO
-- Import the original V2 CSVs into tables created by the schema section above.
-- SQL Server 2017+ on Windows; SQL Server must have read access to the folder.
-- No tables or existing rows are deleted. Non-empty tables are skipped.
-- Each newly loaded table is committed only if its row count matches the original CSV.
-- Verified locally: all 11 CSV headers/order and record counts match the source schema.
-- Not executed against your SQL Server. Existing schema must match the schema section above.
SET NOCOUNT ON;
SET XACT_ABORT ON;

-- Change ONLY this path if your CSV directory has moved. Keep trailing backslash.
DECLARE @DataFolder nvarchar(4000) = NULL;
IF @DataFolder IS NULL THROW 50010, 'Set @DataFolder to the reviewed CSV directory with a trailing separator.', 1;
IF TRY_CONVERT(int, SERVERPROPERTY('ProductMajorVersion')) < 14
    THROW 50000, 'This script requires SQL Server 2017 or newer.', 1;

DECLARE @Files TABLE (seq int PRIMARY KEY, table_name sysname, expected_rows bigint);
INSERT INTO @Files VALUES
(1, N'zone_table', 7),
(2, N'service_table', 2),
(3, N'date_table', 183),
(4, N'user_table', 5000),
(5, N'driver_table', 1000),
(6, N'weather_hourly_table', 30744),
(7, N'driver_session_table', 32981),
(8, N'trip_table', 125923),
(9, N'dispatch_offer_table', 169829),
(10, N'driver_state_interval_table', 689936),
(11, N'supply_15min_table', 245952);

DECLARE @i int = 1, @Table sysname, @Expected bigint, @Before bigint,
        @After bigint, @SQL nvarchar(max), @Path nvarchar(4000), @Message nvarchar(2048);
DECLARE @Results TABLE (table_name sysname, action_taken varchar(20), actual_rows bigint, expected_rows bigint);

WHILE @i <= 11
BEGIN
    SELECT @Table = table_name, @Expected = expected_rows FROM @Files WHERE seq = @i;
    IF OBJECT_ID(N'dbo.' + @Table, N'U') IS NULL
    BEGIN
        SET @Message = N'Missing table dbo.' + @Table + N'. Run the schema section above in Ride_Hailing first.';
        THROW 50001, @Message, 1;
    END;
    SET @SQL = N'SELECT @n = COUNT_BIG(*) FROM dbo.' + QUOTENAME(@Table) + N';';
    EXEC sys.sp_executesql @SQL, N'@n bigint OUTPUT', @n = @Before OUTPUT;
    IF @Before > 0
    BEGIN
        INSERT INTO @Results VALUES (@Table, 'SKIPPED_NONEMPTY', @Before, @Expected);
        PRINT N'SKIPPED (already contains data): dbo.' + @Table;
    END
    ELSE
    BEGIN
        SET @Path = @DataFolder + @Table + N'.csv';
        SET @SQL = N'BULK INSERT dbo.' + QUOTENAME(@Table)
            + N' FROM ''' + REPLACE(@Path, '''', '''''') + N''' WITH (
                FORMAT = ''CSV'', FIRSTROW = 2, CODEPAGE = ''65001'',
                FIELDQUOTE = ''"'', FIELDTERMINATOR = '','',
                ROWTERMINATOR = ''0x0d0a'', KEEPNULLS, CHECK_CONSTRAINTS,
                MAXERRORS = 0
            );';
        BEGIN TRY
            BEGIN TRANSACTION;
            EXEC sys.sp_executesql @SQL;
            SET @SQL = N'SELECT @n = COUNT_BIG(*) FROM dbo.' + QUOTENAME(@Table) + N';';
            EXEC sys.sp_executesql @SQL, N'@n bigint OUTPUT', @n = @After OUTPUT;
            IF @After <> @Expected
            BEGIN
                SET @Message = N'Row count mismatch in dbo.' + @Table + N'. Load rolled back; check CSV file.';
                THROW 50002, @Message, 1;
            END;
            COMMIT TRANSACTION;
            INSERT INTO @Results VALUES (@Table, 'IMPORTED', @After, @Expected);
            PRINT N'IMPORTED: dbo.' + @Table + N' (' + CONVERT(nvarchar(30), @After) + N' rows)';
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
            PRINT N'FAILED: dbo.' + @Table + N'. Earlier completed tables remain loaded; this table was rolled back.';
            THROW;
        END CATCH;
    END;
    SET @i += 1;
END;
SELECT table_name, action_taken, actual_rows, expected_rows,
       CASE WHEN actual_rows = expected_rows THEN 'COUNT_OK' ELSE 'REVIEW_COUNT' END AS count_check
FROM @Results;
-- SKIPPED_NONEMPTY means existing content was preserved, not verified as identical.
