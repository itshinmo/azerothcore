# A ModuleDatabasePool connection sizes MySQLConnection::m_stmts itself, which needs the
# complete MySQLPreparedStatement type and therefore the MySQL client header. Take the include
# directory from the same imported target the database library uses.
if(TARGET mysql)
  target_link_libraries(modules PRIVATE mysql)
endif()

set_property(GLOBAL APPEND PROPERTY ACORE_MODULE_TEST_SOURCES
  "${CMAKE_CURRENT_LIST_DIR}/test/PvpRulesetsTest.cpp")
set_property(GLOBAL APPEND PROPERTY ACORE_MODULE_TEST_INCLUDES
  "${CMAKE_CURRENT_LIST_DIR}/src")
