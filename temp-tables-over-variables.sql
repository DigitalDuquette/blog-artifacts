USE StackOverflow2010
;
GO

CREATE OR ALTER PROCEDURE dbo.usp_identify_inactive_users(
    /*Flag to prevent pushing records into production for testing*/
    @push_to_prod BIT = 0,
    /*Number of months of inactivity to flag (default 24 months)*/
    @months_inactive INT = 24,
    /*Minimum reputation to consider (filters out drive-by accounts)*/
    @min_reputation INT = 100
)
AS
BEGIN
    /*******************************************************************************
     * Identify and Flag Inactive Users
     *
     * Business Rule: Flag users who haven't posted (question or answer) in the
     *                specified number of months, but who have enough reputation
     *                to indicate they were once active contributors.
     *
     * Steps:
     *     - Materialize parameters into temp table  for better development, also avoids parameter sniffing
     *     - Find each user's most recent post activity
     *     - Identify users meeting inactivity criteria
     *     - Update user records if @push_to_prod = 1
     ******************************************************************************/


    DROP TABLE IF EXISTS #params;

    CREATE TABLE #params
    (
        cutoff_date DATETIME,
        current_datetime DATETIME,
        months_inactive INT,
        min_reputation INT,
        pushed_to_prod BIT
    );

    --#region | Materialize parameters
    IF 1 = 1
        BEGIN
            INSERT INTO
                #params
                (
                    cutoff_date,
                    current_datetime,
                    months_inactive,
                    min_reputation,
                    pushed_to_prod
                )
            VALUES
                (
                    DATEADD( MONTH, -@months_inactive, GETDATE( ) ),
                    GETDATE( ),
                    @months_inactive,
                    @min_reputation,
                    @push_to_prod
                );
        END
    --#endregion | Materialize parameters

    --#region | TESTING/DEV (Materialize parameters directly for testing)
    IF 1 = 0
        BEGIN
            /*TESTING/DEV: Highlight and run this INSERT directly to load test values*/
            INSERT INTO
                #params
                (
                    cutoff_date,
                    current_datetime,
                    months_inactive,
                    min_reputation
                )
            VALUES
                (
                    DATEADD( MONTH, -12, '2010-10-31' ),
                    GETDATE( ),
                    12,
                    100
                );
        END
    --#endregion | TESTING/DEV (Materialize parameters directly for testing)

    --#region | Find most recent post activity per user
    DROP TABLE IF EXISTS #user_last_activity;

    SELECT
        p.OwnerUserId AS UserId,
        MAX( p.CreationDate ) AS LastPostDate
    INTO
        #user_last_activity
    FROM dbo.Posts AS p
    WHERE
        p.OwnerUserId IS NOT NULL
        AND p.PostTypeId IN ( 1, 2 ) -- Questions and Answers only
    GROUP BY
        p.OwnerUserId;

    CREATE CLUSTERED INDEX IX_user_last_activity
        ON #user_last_activity ( UserId );
    --#endregion | Find most recent post activity per user

    --#region | Identify inactive users meeting criteria
    DROP TABLE IF EXISTS #inactive_users;

    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS AccountCreated,
        ula.LastPostDate,
        DATEDIFF( MONTH, ula.LastPostDate, (
                                               SELECT
                                                   current_datetime
                                               FROM #params
                                           ) ) AS MonthsInactive
    INTO
        #inactive_users
    FROM dbo.Users AS u
        INNER JOIN #user_last_activity AS ula
            ON u.Id = ula.UserId
    WHERE
        u.Reputation >= (
                            SELECT
                                min_reputation
                            FROM #params
                        )
        AND ula.LastPostDate < (
                                   SELECT
                                       cutoff_date
                                   FROM #params
                               );
    --#endregion | Identify inactive users meeting criteria

    IF @push_to_prod = 1
        BEGIN
            --#region | Update inactive users (example: set a flag in AboutMe)
            UPDATE tgt
            SET /*Bad example, no inactive date/flag, but here we are. */
                AboutMe = tgt.AboutMe + ' [INACTIVE: Flagged '
                    + CONVERT( VARCHAR(10), (
                                                SELECT
                                                    current_datetime
                                                FROM #params
                                            ), 120 ) + ']'
            FROM dbo.Users AS tgt
                INNER JOIN #inactive_users AS iu
                    ON tgt.Id = iu.UserId
            WHERE
                tgt.AboutMe NOT LIKE '%[INACTIVE:%';
            -- Don't double-flag
            --#endregion | Update inactive users (example: set a flag in AboutMe)
        END

    --#region | TESTING/DEV
    IF 1 = 0
        BEGIN
            -- Quick param check
            SELECT *
            FROM #params;

            -- How many users are we looking at?
            SELECT
                COUNT( * ) AS inactive_count
            FROM #inactive_users;

            -- Sample the data
            SELECT TOP 10 *
            FROM #inactive_users
            ORDER BY
                Reputation DESC;

            -- Spot check a specific user
            SELECT *
            FROM #user_last_activity
            WHERE
                UserId = 22656;
        END
    --#endregion | TESTING/DEV

    --#region | CLEANUP
    DROP TABLE IF EXISTS #inactive_users;
    DROP TABLE IF EXISTS #user_last_activity;
    DROP TABLE IF EXISTS #params;
    --#endregion
END
GO
