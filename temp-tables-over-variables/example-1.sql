-- Line 10
DECLARE @CustomerId INT = 22656;
;

-- ... 340 lines of code ...

-- Line 350 - the section you need to debug
SELECT
    1
FROM dbo.Users AS u
WHERE
    u.Id = @CustomerId
;
