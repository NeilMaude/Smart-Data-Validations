/*

	CPC Checking SQL
	Code to create temp tables for checking of CPC data entry in Smart
	
	Neil Maude
	17-January2019

*/

-- create the exclusions table (if and only if doesn't already exist - may have manually entered data in there)
print 'Checking for zCPCCheckerExclusions table'

IF (NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND  TABLE_NAME = 'zCPCCheckerExclusions'))
BEGIN
	print 'Table not found, creating...'
	CREATE TABLE [dbo].[zCPCCheckerExclusions](
       [LedgerAccount] [varchar](20) NULL,
       [Serial] [varchar](20) NULL,
	   [IgnoreCPC] bit NULL,
	   [IgnoreBill] bit NULL,
	   [IgnoreMeter] bit NULL
	) ON [PRIMARY]
END
GO

-- drop the tables we are always going to replace
IF (EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND  TABLE_NAME = 'zCPCChecker'))
BEGIN
	print 'Dropping working zCPCChecker table...'
	DROP TABLE [dbo].[zCPCChecker]
END
GO
IF (EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND  TABLE_NAME = 'zCPCCheckerMachineAverage'))
BEGIN
	print 'Dropping working zCPCCheckerMachineAverage table...'
	DROP TABLE [dbo].[zCPCCheckerMachineAverage]
END
GO

-- create the tables to receive data
print 'Creating fresh working tables...'
CREATE TABLE [dbo].[zCPCChecker] (
	[contractLineId] [varchar](100) NULL,
	[LedgerAccount] [varchar](20) NULL,
	[Serial] [varchar](20) NULL,
	[Machine] [varchar](20) NULL,
	[A4Black] [float] NULL,
	[A4Colour] [float] NULL,
	[A3Black] [float] NULL,
	[A3Colour] [float] NULL,
	[InstallDate] [date] NULL,
	[LastBillDate] [date] NULL,
	[LastBillValue] [money] NULL,
	[LastMeterReadingDate] [date] NULL,					-- will use just one date, the date of the last A4BLACK meter reading
	[IssueBlackColour] bit NULL,					-- issue of A4Black > A4Colour
	[IssueBlackAverage] bit NULL,					-- issue of A4Black outside of machine tolerance
	[IssueBlackLow] bit NULL,						-- issue of A4Black below generic black threshold
	[IssueBlackHigh] bit NULL,						-- issue of A4Black above generic black threshold
	[IssueColourAverage] bit NULL,					-- issue of A4Colour outside of machine tolerance
	[IssueColourLow] bit NULL,						-- issue of A4Colour below generic Colour threshold
	[IssueColourHigh] bit NULL,						-- issue of A4Colour above generic Colour threshold
	[IssueA3BlackLow] bit NULL,						-- issue of A3Black less than required multiple of A4Black
	[IssueA3ColourLow] bit NULL, 					-- issue of A3Colour less than required multiple of A4Colour
	[IssueLastBillAge] bit NULL,					-- issue of last bill outside of required range
	[IssueLastMeterAge] bit NULL					-- issue of last meter reading outside of required range
) ON [PRIMARY]
GO

CREATE TABLE [dbo].[zCPCCheckerMachineAverage] (
	[Machine] [varchar](20) NULL,
	[AvgA4Black] [float] NULL,
	[AvgA4Colour] [float] NULL,
	[AvgA3Black] [float] NULL,
	[AvgA3Colour] [float] NULL,
	[VarA4Black] [float] NULL,
	[VarA4Colour] [float] NULL,
	[VarA3Black] [float] NULL,
	[VarA3Colour] [float] NULL
) ON [PRIMARY]
GO

-- select in the list of active contracted machines

-- calculate the currently used CPCs for each contracted machine

-- calculate the current averages for each machine type

-- calculate any CPC variances

-- find the last billing and meter reading dates for each machine

-- set up any billing / meter reading date issues