CREATE PROCEDURE [retrieve_history]
	(@email    [char(20)])
BEGIN
	DECLARE @house TABLE(BetID INT, BetType varchar(60), BetAmount MONEY, Result varchar(30), HouseID INT) 
	DECLARE @death TABLE(BetID INT, BetType varchar(60), BetAmount MONEY, Result varchar(30), CharID INT)
	DECLARE @resurrect TABLE(BetID INT, BetType varchar(60), BetAmount MONEY, Result varchar(30), CharID INT)

	INSERT INTO @house
	SELECT b.BetID, b.BetAmount, b.Result, h.HouseID
	FROM [Bet] AS b, [HouseBet] AS h
	WHERE @email = b.UserEmail AND b.BetID = h.BetID 

	INSERT INTO @death
	SELECT b.BetID, b.BetAmount, b.Result, d.CharID
	FROM [Bet] AS b, [DeathBet] AS d
	WHERE @email = b.UserEmail AND b.BetID = d.CharID

	INSERT INTO @resurrect
	SELECT b.BetID, b.BetAmount, b.Result, r.CharID
	FROM [Bet] AS b, [RFDBet] AS r
	WHERE @email = UserEmail AND b.BetID = r.BetID

	DECLARE @history TABLE(BetID INT, BetType varchar(60), BetAmount MONEY, Result varchar(30), Name varchar(80))

	INSERT INTO @history
	SELECT @house.BetID, @house.BetType, @house.BetAmount, @house.Result, House.Name
	FROM @house, [House]
	WHERE @house.HouseID = House.HouseID 

	INSERT INTO @history
	SELECT @death.BetID, @death.BetType, @death.BetAmount, @death.Result, Person.Name
	FROM @death, [Person]
	WHERE @death.CharID = Person.CharID

	INSERT INTO @history
	SELECT @resurrect.BetID, @resurrect.BetType, @resurrect.BetAmount, @resurrect.Result, Person.Name
	FROM @resurrect, [Person]
	WHERE @resurrect.CharID = Person.CharID
END