# A ModuleDatabasePool connection sizes MySQLConnection::m_stmts itself, which needs the
# complete MySQLPreparedStatement type and therefore the MySQL client header. Take the include
# directory from the same imported target the database library uses.
if(TARGET mysql)
  target_link_libraries(modules PRIVATE mysql)
endif()
