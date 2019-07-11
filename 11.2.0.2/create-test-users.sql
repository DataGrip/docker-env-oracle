create user Test_User identified by test
                      default tablespace users
                      temporary tablespace temp
                      quota unlimited on users
/

grant connect, development
    to Test_User with admin option
/

create user Test_Admin identified by test
                       default tablespace users
                       temporary tablespace temp
                       quota unlimited on users
/

grant connect, development
    to Test_User with admin option
/

grant select any dictionary
    to Test_Admin
/
