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
	[CustomerId] [varchar](50) NULL,
	[LedgerAccount] [varchar](20) NULL,
	[Serial] [varchar](50) NULL,
	[Machine] [varchar](100) NULL,
	[ProductGroup] [varchar](20) NULL,
	[ContractType] [varchar](100) NULL,
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
	[MIF] int NULL,
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

-- General parameters
DECLARE @MIN_BLACK float
DECLARE @MAX_BLACK float
DECLARE @MIN_COLOUR float
DECLARE @MAX_COLOUR float
DECLARE @BLACK_VARIANCE_ALLOWED float
DECLARE @COLOUR_VARIANCE_ALLOWED float
DECLARE @A3_MULTIPLE_REQUIRED float

SET @MIN_BLACK = 0.2						-- issue if below this value
SET @MAX_BLACK = 2.0						-- issue if above this value
SET @MIN_COLOUR = 2.0					-- issue if below this value
SET @MAX_COLOUR = 9.0					-- issue if above this value
SET @BLACK_VARIANCE_ALLOWED = 0.1		-- issue if varys from average by more than this percentage
SET @COLOUR_VARIANCE_ALLOWED = 0.1		-- as per mono
SET @A3_MULTIPLE_REQUIRED = 1.5			-- A3 cost must be at least this multiple of the A4 cost

-- select in the list of active machines, contracted / T&M and out-of-area
insert into [dbo].[zCPCChecker] (contractLineId, CustomerId, Serial, Machine, ProductGroup, ContractType, InstallDate)
	select C.contractLineId, C.customerId, C.serial, C.productId, C.productGroup, C.serviceLevelDesc, C.startDate
	from dbo.contractline C 
	where 
	IsNull(serial, '') <> ''									-- must be a serial item (takes out contract headers)
	and IsNull(cancelledDateTime, '') = ''						-- must not be cancelled
	and Cast(startDate as datetime) <= GETDATE()				-- must have a contract which has started
	and Cast(expiryDate as datetime) >= GETDATE()				-- must have a future expiry date (i.e. not already expired)
	and (not ledgerNo like 'S-S001%')							-- not Stratas acccounts 
	and (not serviceLevelDesc Like '36%')						-- exclude 36 month warranty case
	and (not serviceLevelDesc Like 'Strat%')					-- exclude Stratas machines held in Arena stock/showroom
	and (not serviceLevelDesc Like '12 Month%')					-- exclude 12 month warranty
	and (productGroup in ('COP','PRI'))

update [dbo].[zCPCChecker] set LedgerAccount = (select top 1 LedgerAccount from dbo.customer where dbo.customer.customerId = dbo.zCPCChecker.CustomerId)

-- calculate the currently used CPCs for each contracted machine, from dbo.contractlinetierprice
update [dbo].[zCPCChecker] set A4Black = (select min(tierPrice)*100 from dbo.contractlinetierpricing P where P.contractLineId = dbo.zCPCChecker.contractLineId and meterTypeId = 'A4BLACK')
update [dbo].[zCPCChecker] set A4Colour = (select min(tierPrice)*100 from dbo.contractlinetierpricing P where P.contractLineId = dbo.zCPCChecker.contractLineId and meterTypeId = 'A4COLOUR')
update [dbo].[zCPCChecker] set A3Black = (select min(tierPrice)*100 from dbo.contractlinetierpricing P where P.contractLineId = dbo.zCPCChecker.contractLineId and meterTypeId = 'A3BLACK')
update [dbo].[zCPCChecker] set A3Colour = (select min(tierPrice)*100 from dbo.contractlinetierpricing P where P.contractLineId = dbo.zCPCChecker.contractLineId and meterTypeId = 'A3COLOUR')

-- calculate the current averages for each machine type
insert into [dbo].[zCPCCheckerMachineAverage] (Machine) select distinct Machine from [dbo].[zCPCChecker]
update [dbo].[zCPCCheckerMachineAverage] 
	set AvgA4Black = (select AVG(A4Black) from [dbo].[zCPCChecker] where [dbo].[zCPCChecker].[Machine] = [dbo].[zCPCCheckerMachineAverage].Machine
						and IsNull(A4Black,0) > 0)
update [dbo].[zCPCCheckerMachineAverage] 
	set AvgA4Colour = (select AVG(A4Colour) from [dbo].[zCPCChecker] where [dbo].[zCPCChecker].[Machine] = [dbo].[zCPCCheckerMachineAverage].Machine
						and IsNull(A4Colour,0) > 0)
update [dbo].[zCPCCheckerMachineAverage] 
	set AvgA3Black = (select AVG(A3Black) from [dbo].[zCPCChecker] where [dbo].[zCPCChecker].[Machine] = [dbo].[zCPCCheckerMachineAverage].Machine
						and IsNull(A3Black,0) > 0)
update [dbo].[zCPCCheckerMachineAverage] 
	set AvgA3Colour = (select AVG(A3Colour) from [dbo].[zCPCChecker] where [dbo].[zCPCChecker].[Machine] = [dbo].[zCPCCheckerMachineAverage].Machine
						and IsNull(A3Colour,0) > 0)
update [dbo].[zCPCCheckerMachineAverage] set MIF = (select count(*) from [dbo].[zCPCChecker] where [dbo].[zCPCChecker].[Machine] = [dbo].[zCPCCheckerMachineAverage].Machine)

-- calculate any CPC variances / issues
update [dbo].[zCPCChecker] set IssueBlackColour = 0
update [dbo].[zCPCChecker] set IssueBlackAverage = 0
update [dbo].[zCPCChecker] set IssueBlackLow = 0
update [dbo].[zCPCChecker] set IssueBlackHigh = 0 
update [dbo].[zCPCChecker] set IssueColourAverage = 0
update [dbo].[zCPCChecker] set IssueColourLow = 0
update [dbo].[zCPCChecker] set IssueColourHigh = 0 
update [dbo].[zCPCChecker] set IssueA3BlackLow = 0
update [dbo].[zCPCChecker] set IssueA3ColourLow = 0

update [dbo].[zCPCChecker] set IssueBlackColour = 1 where A4Black > A4Colour
update [dbo].[zCPCChecker] set IssueBlackAverage = 1 
	where A4Black < (1.0 - @BLACK_VARIANCE_ALLOWED) * (select AvgA4Black from [dbo].[zCPCCheckerMachineAverage] where [dbo].[zCPCCheckerMachineAverage].Machine = [dbo].[zCPCChecker].Machine)
update [dbo].[zCPCChecker] set IssueBlackLow = 1 where A3Black < @MIN_BLACK
update [dbo].[zCPCChecker] set IssueBlackHigh = 1 where A3Black > @MAX_BLACK
update [dbo].[zCPCChecker] set IssueColourLow = 1 where A4Colour < @MIN_COLOUR
update [dbo].[zCPCChecker] set IssueColourHigh = 1 where A4Colour > @MAX_COLOUR
update [dbo].[zCPCChecker] set IssueColourAverage = 1 
	where A4Black < (1.0 - @COLOUR_VARIANCE_ALLOWED) * (select AvgA4Colour from [dbo].[zCPCCheckerMachineAverage] where [dbo].[zCPCCheckerMachineAverage].Machine = [dbo].[zCPCChecker].Machine)
update [dbo].[zCPCChecker] set IssueA3BlackLow = 1 where A3Black < @A3_MULTIPLE_REQUIRED * A4Black
update [dbo].[zCPCChecker] set IssueA3ColourLow = 1 where A3Colour < @A3_MULTIPLE_REQUIRED * A4Colour

-- find the last billing and meter reading dates for each machine  
-- this takes ages as the dbo.invoiceline table can't be indexed on contractLineId...
update [dbo].[zCPCChecker] set LastBillDate = 
	(select top 1 postedDateTime from dbo.invoiceline where dbo.invoiceline.contractLineId = REPLACE([dbo].[zCPCChecker].contractLineId,'*','_') and invoiceTemplateId = 'METER' order by postedDateTime DESC)

IF EXISTS (SELECT *  FROM sys.indexes  WHERE name='CPC_CHECK_i3' AND object_id = OBJECT_ID('[dbo].[meterreading]'))
BEGIN
    DROP INDEX dbo.meterreading.CPC_CHECK_i3
END
CREATE INDEX CPC_CHECK_i3 on dbo.meterreading (contractLineId)
GO
update dbo.zCPCChecker set LastMeterReadingDate = (select top 1 readingDateTime from dbo.meterreading where dbo.meterreading.contractLineId = dbo.zCPCChecker.contractLineId order by readingDateTime DESC)
DROP INDEX dbo.meterreading.CPC_CHECK_i3

-- set up any billing / meter reading date issues
DECLARE @MONTHS_BILL_INTERVAL int
SET @MONTHS_BILL_INTERVAL = 6
update dbo.zCPCChecker set IssueLastBillAge = 0
update dbo.zCPCChecker set IssueLastBillAge = 1 where DATEDIFF(m,LastBillDate,getDate()) >= @MONTHS_BILL_INTERVAL

DECLARE @MONTHS_METER_INTERVAL int
SET @MONTHS_METER_INTERVAL = 6
update dbo.zCPCChecker set IssueLastMeterAge = 0
update dbo.zCPCChecker set IssueLastMeterAge = 1 where DATEDIFF(m,LastMeterReadingDate,getDate()) >= @MONTHS_METER_INTERVAL

-- some basic statistics
select count(*) [MIF] from [dbo].[zCPCChecker] 
select count(*) [BlackOverColour] from [dbo].[zCPCChecker] where IssueBlackColour = 1
select * from [dbo].[zCPCChecker] where IssueBlackColour = 1

-- test code below here



select * from [dbo].[zCPCChecker] order by LastBillDate desc
select top 10 * from dbo.invoiceline where contractLineId = REPLACE('514204*00005','*','_')

select top 10 * from dbo.invoiceline
select top 10 * from dbo.meterreading where serial = 'C2LC11585'

select * from [dbo].[zCPCChecker] where IsNull(lastbilldate,'') <> ''
select * from [dbo].[zCPCCheckerMachineAverage] order by machine

select * from [dbo].[zCPCChecker] where machine = 'E283'
