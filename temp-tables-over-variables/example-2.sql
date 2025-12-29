BEGIN
    DECLARE @CustomerId INT = 22656
    DROP TABLE IF EXISTS #CustomerId;
    CREATE TABLE #CustomerId
    (
        CustomerId INT
    );
    INSERT INTO
        #CustomerId
    VALUES
        ( @CustomerId );
END

-- ... 340 lines of code ...

-- Line 350 - the section you need to debug
SELECT
    1
FROM dbo.Users AS u
WHERE
    u.Id IN (
                SELECT
                    CustomerId
                FROM #CustomerId
            )
;