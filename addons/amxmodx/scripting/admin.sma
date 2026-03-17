// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Admin Base Plugin
//

// Uncomment for SQL version
// #define USING_SQL

#include <amxmodx>
#include <amxmisc>
#if defined USING_SQL
#include <sqlx>
#endif

//new Vector:AdminList;

new AdminCount;

new PLUGINNAME[] = "AMX Mod X"

#define ADMIN_LOOKUP	(1<<0)
#define ADMIN_NORMAL	(1<<1)
#define ADMIN_STEAM		(1<<2)
#define ADMIN_IPADDR	(1<<3)
#define ADMIN_NAME		(1<<4)

new bool:g_CaseSensitiveName[MAX_PLAYERS + 1];

// Проверяет, что переданная строка соответствует формату IPv4-адреса.
bool:is_valid_ipv4(const ip[])
{
	new len = strlen(ip)

	if (len < 7 || len > 15)
		return false

	new dots, digits

	for (new i = 0; i < len; i++)
	{
		if (ip[i] == '.')
		{
			if (digits < 1 || digits > 3)
				return false

			dots++
			digits = 0
		}
		else if (ip[i] >= '0' && ip[i] <= '9')
		{
			digits++

			if (digits > 3)
				return false
		}
		else
		{
			return false
		}
	}

	return dots == 3 && digits >= 1 && digits <= 3
}

// Проверяет, является ли год високосным.
bool:is_leap_year(year)
{
	return ((year % 4 == 0 && year % 100 != 0) || (year % 400 == 0));
}

// Возвращает количество дней в переданном месяце указанного года.
get_days_in_month(month, year)
{
	static const daysPerMonth[] = { 31,28,31,30,31,30,31,31,30,31,30,31 };

	if (month == 2 && is_leap_year(year))
		return 29;

	return daysPerMonth[month - 1];
}

// Проверяет корректность даты в формате день/месяц/год.
bool:is_valid_date(day, month, year)
{
	if (year < 1970 || month < 1 || month > 12)
		return false;

	new maxDay = get_days_in_month(month, year);
	return day >= 1 && day <= maxDay;
}

// Преобразует дату в Unix-время (секунды от 01.01.1970 00:00:00).
date_to_unix(day, month, year)
{
	new days;

	for (new y = 1970; y < year; y++)
	{
		days += is_leap_year(y) ? 366 : 365;
	}

	for (new m = 1; m < month; m++)
	{
		days += get_days_in_month(m, year);
	}

	days += day - 1;
	return days * 86400;
}

// Разбирает дату вида dd.mm.yyyy в отдельные целочисленные части.
bool:parse_date_string(dateString[], &day, &month, &year)
{
	new buffer[24], tokenDay[8], tokenMonth[8], tokenYear[8];
	copy(buffer, charsmax(buffer), dateString);
	replace_all(buffer, charsmax(buffer), ".", " ");

	if (parse(buffer, tokenDay, charsmax(tokenDay), tokenMonth, charsmax(tokenMonth), tokenYear, charsmax(tokenYear)) < 3)
		return false;

	day = str_to_num(tokenDay);
	month = str_to_num(tokenMonth);
	year = str_to_num(tokenYear);

	return is_valid_date(day, month, year);
}

// Проверяет, что строка состоит только из цифр и может быть интерпретирована как количество дней.
bool:is_numeric_string(value[])
{
	new len = strlen(value);

	if (!len)
		return false;

	for (new i = 0; i < len; i++)
	{
		if (value[i] < '0' || value[i] > '9')
			return false;
	}

	return true;
}

// Разбирает период доступа вида "dd.mm.yyyy - dd.mm.yyyy" в две Unix-метки времени.
bool:parse_access_range(range[], &startUnix, &endUnix)
{
	if (contain(range, "-") == -1)
		return false;

	new buffer[64], left[24], right[24], day, month, year;
	copy(buffer, charsmax(buffer), range);
	strtok(buffer, left, charsmax(left), right, charsmax(right), '-');
	trim(left);
	trim(right);

	if (!parse_date_string(left, day, month, year))
		return false;

	startUnix = date_to_unix(day, month, year);

	if (!parse_date_string(right, day, month, year))
		return false;

	endUnix = date_to_unix(day, month, year) + 86399;
	return endUnix >= startUnix;
}

// pcvars
new amx_mode;
new amx_password_field;
new amx_default_access;

// Инициализирует плагин, регистрирует cvar/команды и запускает первичную загрузку админов.
public plugin_init()
{
#if defined USING_SQL
	register_plugin("Admin Base (SQL)", AMXX_VERSION_STR, "AMXX Dev Team")
#else
	register_plugin("Admin Base", AMXX_VERSION_STR, "AMXX Dev Team")
#endif
	register_dictionary("admin.txt")
	register_dictionary("common.txt")
	amx_mode=register_cvar("amx_mode", "1", FCVAR_PROTECTED)
	amx_password_field=register_cvar("amx_password_field", "_pw", FCVAR_PROTECTED)
	amx_default_access=register_cvar("amx_default_access", "", FCVAR_PROTECTED)

	register_cvar("amx_vote_ratio", "0.02")
	register_cvar("amx_vote_time", "10")
	register_cvar("amx_vote_answers", "1")
	register_cvar("amx_vote_delay", "60")
	register_cvar("amx_last_voting", "0")
	register_cvar("amx_show_activity", "2", FCVAR_PROTECTED)
	register_cvar("amx_votekick_ratio", "0.40")
	register_cvar("amx_voteban_ratio", "0.40")
	register_cvar("amx_votemap_ratio", "0.40")

	set_cvar_float("amx_last_voting", 0.0)

#if defined USING_SQL
	register_srvcmd("amx_sqladmins", "adminSql")
	register_cvar("amx_sql_table", "admins", FCVAR_PROTECTED)
#endif
	register_cvar("amx_sql_host", "127.0.0.1", FCVAR_PROTECTED)
	register_cvar("amx_sql_user", "root", FCVAR_PROTECTED)
	register_cvar("amx_sql_pass", "", FCVAR_PROTECTED)
	register_cvar("amx_sql_db", "amx", FCVAR_PROTECTED)
	register_cvar("amx_sql_type", "mysql", FCVAR_PROTECTED)
	register_cvar("amx_sql_timeout", "60", FCVAR_PROTECTED)

	register_concmd("amx_reloadadmins", "cmdReload", ADMIN_CFG)
	register_concmd("amx_addadmin", "addadminfn", ADMIN_RCON, "<playername|auth> <accessflags> [password] [authtype] - add specified player as an admin to users.ini")

	remove_user_flags(0, read_flags("z"))		// Remove 'user' flag from server rights

	new configsDir[64]
	get_configsdir(configsDir, charsmax(configsDir))

	server_cmd("exec %s/sql.cfg", configsDir)

	// Create a vector of 5 cells to store the info.
	//AdminList=vector_create(5);

	
#if defined USING_SQL
	server_cmd("amx_sqladmins")
#else
	format(configsDir, 63, "%s/users.ini", configsDir)
	loadSettings(configsDir)					// Load admins accounts
#endif
}

// Сбрасывает признак чувствительности к регистру для подключающегося игрока.
public client_connect(id)
{
	g_CaseSensitiveName[id] = false;
}

// Консольная команда amx_addadmin: определяет тип идентификатора и добавляет администратора.
public addadminfn(id, level, cid)
{
	if (!cmd_access(id, level, cid, 3))
		return PLUGIN_HANDLED
		
	new idtype = ADMIN_STEAM | ADMIN_LOOKUP

	if (read_argc() >= 5)
	{
		new t_arg[16]
		read_argv(4, t_arg, charsmax(t_arg))
		
		if (equali(t_arg, "steam") || equali(t_arg, "steamid") || equali(t_arg, "auth"))
		{
			idtype = ADMIN_STEAM
		}
		else if (equali(t_arg, "ip"))
		{
			idtype = ADMIN_IPADDR
		}
		else if (equali(t_arg, "name") || equali(t_arg, "nick"))
		{
			idtype = ADMIN_NAME
			
			if (equali(t_arg, "name"))
				idtype |= ADMIN_LOOKUP
		} else {
			console_print(id, "[%s] Unknown id type ^"%s^", use one of: steamid, ip, name", PLUGINNAME, t_arg)
			return PLUGIN_HANDLED
		}
	}

	new arg[33]
	read_argv(1, arg, charsmax(arg))
	new player = -1
	
	if (idtype & ADMIN_STEAM)
	{
		if (containi(arg, "STEAM_0:") == -1)
		{
			idtype |= ADMIN_LOOKUP
			player = cmd_target(id, arg, CMDTARGET_ALLOW_SELF | CMDTARGET_NO_BOTS)
		} else {
			new _steamid[44]
			static _players[MAX_PLAYERS], _num, _pv
			get_players(_players, _num)
			for (new _i=0; _i<_num; _i++)
			{
				_pv = _players[_i]
				get_user_authid(_pv, _steamid, charsmax(_steamid))
				if (!_steamid[0])
					continue
				if (equal(_steamid, arg))
				{
					player = _pv
					break
				}
			}	
			if (player < 1)
			{
				idtype &= ~ADMIN_LOOKUP
			}		
		}
	}
	else if (idtype & ADMIN_NAME)
	{
		player = cmd_target(id, arg, CMDTARGET_ALLOW_SELF | CMDTARGET_NO_BOTS)
		
		if (player)
			idtype |= ADMIN_LOOKUP
		else
			idtype &= ~ADMIN_LOOKUP
	}
	else if (idtype & ADMIN_IPADDR)
	{
		if (!is_valid_ipv4(arg))
		{
			idtype |= ADMIN_LOOKUP
			player = find_player("dh", arg)
		}
	}
	
	if (idtype & ADMIN_LOOKUP && !player)
	{
		console_print(id, "%L", id, "CL_NOT_FOUND")
		return PLUGIN_HANDLED
	}
	
	new flags[64]
	read_argv(2, flags, charsmax(flags))

	new password[64]
	if (read_argc() >= 4) {
		read_argv(3, password, charsmax(password))
	}

	new auth[33]
	new Comment[MAX_NAME_LENGTH]; // name of player to pass to comment field
	if (idtype & ADMIN_LOOKUP)
	{
		get_user_name(player, Comment, charsmax(Comment))
		if (idtype & ADMIN_STEAM)
		{
			get_user_authid(player, auth, charsmax(auth))
		}
		else if (idtype & ADMIN_IPADDR)
		{
			get_user_ip(player, auth, charsmax(auth), 1)
		}
		else if (idtype & ADMIN_NAME)
		{
			get_user_name(player, auth, charsmax(auth))
		}
	} else {
		copy(auth, charsmax(auth), arg)
	}
	
	new type[16], len
	
	if (idtype & ADMIN_STEAM)
		len += format(type[len], charsmax(type) - len, "c")
	else if (idtype & ADMIN_IPADDR)
		len += format(type[len], charsmax(type) - len, "d")
	
	if (strlen(password) > 0)
		len += format(type[len], charsmax(type) - len, "a")
	else
		len += format(type[len], charsmax(type) - len, "e")
	
	AddAdmin(id, auth, flags, password, type, Comment)
	cmdReload(id, ADMIN_CFG, 0)

	if (player > 0)
	{
		new name[MAX_NAME_LENGTH]
		get_user_info(player, "name", name, charsmax(name))
		accessUser(player, name)
	}

	return PLUGIN_HANDLED
}

// Добавляет админа в users.ini (или SQL при соответствующей сборке), избегая дубликатов.
AddAdmin(id, auth[], accessflags[], password[], flags[], comment[]="")
{
#if defined USING_SQL
	new error[128], errno

	new Handle:info = SQL_MakeStdTuple()
	new Handle:sql = SQL_Connect(info, errno, error, charsmax(error))
	
	if (sql == Empty_Handle)
	{
		server_print("[AMXX] %L", LANG_SERVER, "SQL_CANT_CON", error)
		//backup to users.ini
#endif
		// Make sure that the users.ini file exists.
		new configsDir[64]
		get_configsdir(configsDir, charsmax(configsDir))
		format(configsDir, charsmax(configsDir), "%s/users.ini", configsDir)

		if (!file_exists(configsDir))
		{
			console_print(id, "[%s] File ^"%s^" doesn't exist.", PLUGINNAME, configsDir)
			return
		}

		// Make sure steamid isn't already in file.
		new line = 0, textline[256], len
		const SIZE = 63
		new line_steamid[SIZE + 1], line_password[SIZE + 1], line_accessflags[SIZE + 1], line_flags[SIZE + 1], parsedParams
		
		// <name|ip|steamid> <password> <access flags> <account flags>
		while ((line = read_file(configsDir, line, textline, charsmax(textline), len)))
		{
			if (len == 0 || equal(textline, ";", 1))
				continue // comment line

			parsedParams = parse(textline, line_steamid, SIZE, line_password, SIZE, line_accessflags, SIZE, line_flags, SIZE)
			
			if (parsedParams != 4)
				continue	// Send warning/error?
			
			if (containi(line_flags, flags) != -1 && equal(line_steamid, auth))
			{
				console_print(id, "[%s] %s already exists!", PLUGINNAME, auth)
				return
			}
		}

		// If we came here, steamid doesn't exist in users.ini. Add it.
		new linetoadd[512]
		
		if (comment[0]==0)
		{
			formatex(linetoadd, charsmax(linetoadd), "^r^n^"%s^" ^"%s^" ^"%s^" ^"%s^"", auth, password, accessflags, flags)
		}
		else
		{
			formatex(linetoadd, charsmax(linetoadd), "^r^n^"%s^" ^"%s^" ^"%s^" ^"%s^" ; %s", auth, password, accessflags, flags, comment)
		}
		console_print(id, "Adding:^n%s", linetoadd)

		if (!write_file(configsDir, linetoadd))
			console_print(id, "[%s] Failed writing to %s!", PLUGINNAME, configsDir)
#if defined USING_SQL
	}
	
	new table[32]
	
	get_cvar_string("amx_sql_table", table, charsmax(table))
	
	new Handle:query = SQL_PrepareQuery(sql, "SELECT * FROM `%s` WHERE (`auth` = '%s')", table, auth)

	if (!SQL_Execute(query))
	{
		SQL_QueryError(query, error, charsmax(error))
		server_print("[AMXX] %L", LANG_SERVER, "SQL_CANT_LOAD_ADMINS", error)
		console_print(id, "[AMXX] %L", LANG_SERVER, "SQL_CANT_LOAD_ADMINS", error)
	} else if (SQL_NumResults(query)) {
		console_print(id, "[%s] %s already exists!", PLUGINNAME, auth)
	} else {
		console_print(id, "Adding to database:^n^"%s^" ^"%s^" ^"%s^" ^"%s^"", auth, password, accessflags, flags)
	
		SQL_QueryAndIgnore(sql, "REPLACE INTO `%s` (`auth`, `password`, `access`, `flags`) VALUES ('%s', '%s', '%s', '%s')", table, auth, password, accessflags, flags)
	}
	
	SQL_FreeHandle(query)
	SQL_FreeHandle(sql)
	SQL_FreeHandle(info)
#endif

}

// Загружает администраторов из users.ini, обрабатывает период доступа и обновляет устаревший формат.
loadSettings(szFilename[])
{
	new line, len, text[512];
	new flags[32], access[32], authData[44], password[32], accessPeriod[64];

	while ((line = read_file(szFilename, line, text, charsmax(text), len)))
	{
		new lineIndex = line - 1;
		trim(text);

		if (!text[0] || text[0] == ';')
			continue;

		// Отделяем служебный комментарий, чтобы не потерять его при возможной перезаписи строки.
		new parsedPart[512], inlineComment[192];
		copy(parsedPart, charsmax(parsedPart), text);
		new commentPos = contain(parsedPart, ";");

		if (commentPos != -1)
		{
			new outPos;
			for (new i = commentPos + 1; parsedPart[i] && outPos < charsmax(inlineComment); i++)
			{
				inlineComment[outPos++] = parsedPart[i];
			}
			inlineComment[outPos] = '^0';
			parsedPart[commentPos] = '^0';
			trim(parsedPart);
			trim(inlineComment);
		}
		else
		{
			inlineComment[0] = '^0';
		}

		flags[0] = '^0';
		access[0] = '^0';
		authData[0] = '^0';
		password[0] = '^0';
		accessPeriod[0] = '^0';

		new parsed = parse(parsedPart, authData, charsmax(authData), password, charsmax(password), access, charsmax(access), flags, charsmax(flags), accessPeriod, charsmax(accessPeriod));
		if (parsed < 4)
			continue;

		if (parsed < 5)
			copy(accessPeriod, charsmax(accessPeriod), "0");

		new bool:allowAccess = true;
		new bool:rewriteLine = false;

		if (!equal(accessPeriod, "0"))
		{
			if (is_numeric_string(accessPeriod))
			{
				// Если указан срок в днях, сразу разворачиваем его в даты начала/окончания и сохраняем в файл.
				new days = str_to_num(accessPeriod);
				new now = get_systime();
				new startDate[16], endDate[16];
				format_time(startDate, charsmax(startDate), "%d.%m.%Y", now);
				format_time(endDate, charsmax(endDate), "%d.%m.%Y", now + ((days > 0 ? (days - 1) : 0) * 86400));
				formatex(accessPeriod, charsmax(accessPeriod), "%s - %s", startDate, endDate);
				rewriteLine = true;
			}
			else
			{
				// Для диапазона дат проверяем, что текущий момент находится внутри периода действия прав.
				new startUnix, endUnix;
				if (parse_access_range(accessPeriod, startUnix, endUnix))
				{
					new now = get_systime();
					allowAccess = (now >= startUnix && now <= endUnix);
				}
				else
				{
					allowAccess = false;
				}
			}
		}

		if (rewriteLine)
		{
			new rewritten[512];
			if (inlineComment[0])
				formatex(rewritten, charsmax(rewritten), "^"%s^" ^"%s^" ^"%s^" ^"%s^" ^"%s^" ; %s", authData, password, access, flags, accessPeriod, inlineComment);
			else
				formatex(rewritten, charsmax(rewritten), "^"%s^" ^"%s^" ^"%s^" ^"%s^" ^"%s^"", authData, password, access, flags, accessPeriod);

			write_file(szFilename, rewritten, lineIndex);
		}

		if (!allowAccess)
			continue;

		admins_push(authData, password, read_flags(access), read_flags(flags));
		AdminCount++;
	}

	if (AdminCount == 1)
	{
		server_print("[AMXX] %L", LANG_SERVER, "LOADED_ADMIN");
	}
	else
	{
		server_print("[AMXX] %L", LANG_SERVER, "LOADED_ADMINS", AdminCount);
	}
	
	return 1;
}

#if defined USING_SQL
// Загружает администраторов из SQL-базы (резервный путь — users.ini).
public adminSql()
{
	new table[32], error[128], type[12], errno
	
	new Handle:info = SQL_MakeStdTuple()
	new Handle:sql = SQL_Connect(info, errno, error, charsmax(error))
	
	get_cvar_string("amx_sql_table", table, charsmax(table))
	
	SQL_GetAffinity(type, charsmax(type))
	
	if (sql == Empty_Handle)
	{
		server_print("[AMXX] %L", LANG_SERVER, "SQL_CANT_CON", error)
		
		//backup to users.ini
		new configsDir[64]
		
		get_configsdir(configsDir, charsmax(configsDir))
		format(configsDir, charsmax(configsDir), "%s/users.ini", configsDir)
		loadSettings(configsDir) // Load admins accounts

		return PLUGIN_HANDLED
	}

	new Handle:query
	
	if (equali(type, "sqlite"))
	{
		if (!sqlite_TableExists(sql, table))
		{
			SQL_QueryAndIgnore(sql, "CREATE TABLE %s ( auth TEXT NOT NULL DEFAULT '', password TEXT NOT NULL DEFAULT '', access TEXT NOT NULL DEFAULT '', flags TEXT NOT NULL DEFAULT '' )", table)
		}

		query = SQL_PrepareQuery(sql, "SELECT auth, password, access, flags FROM %s", table)
	} else {
		SQL_QueryAndIgnore(sql, "CREATE TABLE IF NOT EXISTS `%s` ( `auth` VARCHAR( 32 ) NOT NULL, `password` VARCHAR( 32 ) NOT NULL, `access` VARCHAR( 32 ) NOT NULL, `flags` VARCHAR( 32 ) NOT NULL ) COMMENT = 'AMX Mod X Admins'", table)
		query = SQL_PrepareQuery(sql,"SELECT `auth`,`password`,`access`,`flags` FROM `%s`", table)
	}

	if (!SQL_Execute(query))
	{
		SQL_QueryError(query, error, charsmax(error))
		server_print("[AMXX] %L", LANG_SERVER, "SQL_CANT_LOAD_ADMINS", error)
	} else if (!SQL_NumResults(query)) {
		server_print("[AMXX] %L", LANG_SERVER, "NO_ADMINS")
	} else {
		
		AdminCount = 0
		
		/** do this incase people change the query order and forget to modify below */
		new qcolAuth = SQL_FieldNameToNum(query, "auth")
		new qcolPass = SQL_FieldNameToNum(query, "password")
		new qcolAccess = SQL_FieldNameToNum(query, "access")
		new qcolFlags = SQL_FieldNameToNum(query, "flags")
		
		new AuthData[44];
		new Password[44];
		new Access[32];
		new Flags[32];
		
		while (SQL_MoreResults(query))
		{
			SQL_ReadResult(query, qcolAuth, AuthData, charsmax(AuthData));
			SQL_ReadResult(query, qcolPass, Password, charsmax(Password));
			SQL_ReadResult(query, qcolAccess, Access, charsmax(Access));
			SQL_ReadResult(query, qcolFlags, Flags, charsmax(Flags));
	
			admins_push(AuthData,Password,read_flags(Access),read_flags(Flags));
	
			++AdminCount;
			SQL_NextRow(query)
		}
	
		if (AdminCount == 1)
		{
			server_print("[AMXX] %L", LANG_SERVER, "SQL_LOADED_ADMIN")
		}
		else
		{
			server_print("[AMXX] %L", LANG_SERVER, "SQL_LOADED_ADMINS", AdminCount)
		}
		
		SQL_FreeHandle(query)
		SQL_FreeHandle(sql)
		SQL_FreeHandle(info)
	}
	
	return PLUGIN_HANDLED
}
#endif

// Перезагружает список администраторов из источника (users.ini или SQL).
public cmdReload(id, level, cid)
{
	if (!cmd_access(id, level, cid, 1))
		return PLUGIN_HANDLED

	//strip original flags (patch submitted by mrhunt)
	remove_user_flags(0, read_flags("z"))
	
	admins_flush();

#if !defined USING_SQL
	new filename[128]
	
	get_configsdir(filename, charsmax(filename))
	format(filename, charsmax(filename), "%s/users.ini", filename)

	AdminCount = 0;
	loadSettings(filename);		// Re-Load admins accounts

	if (id != 0)
	{
		if (AdminCount == 1)
		{
			console_print(id, "[AMXX] %L", LANG_SERVER, "LOADED_ADMIN");
		}
		else
		{
			console_print(id, "[AMXX] %L", LANG_SERVER, "LOADED_ADMINS", AdminCount);
		}
	}
#else
	AdminCount = 0
	adminSql()

	if (id != 0)
	{
		if (AdminCount == 1)
			console_print(id, "[AMXX] %L", LANG_SERVER, "SQL_LOADED_ADMIN")
		else
			console_print(id, "[AMXX] %L", LANG_SERVER, "SQL_LOADED_ADMINS", AdminCount)
	}
#endif

	new players[MAX_PLAYERS], num, pv
	new name[MAX_NAME_LENGTH]
	get_players(players, num)
	for (new i=0; i<num; i++)
	{
		pv = players[i]
		get_user_name(pv, name, charsmax(name))
		accessUser(pv, name)
	}

	return PLUGIN_HANDLED
}

// Ищет подходящую учётную запись администратора и применяет права при успешной проверке.
getAccess(id, name[], authid[], ip[], password[])
{
	new index = -1
	new result = 0
	
	static Count;
	static Flags;
	static Access;
	static AuthData[44];
	static Password[32];
	
	g_CaseSensitiveName[id] = false;

	Count=admins_num();
	for (new i = 0; i < Count; ++i)
	{
		// Последовательно проверяем все типы привязки: steamid, ip или имя/тег.
		Flags=admins_lookup(i,AdminProp_Flags);
		admins_lookup(i,AdminProp_Auth,AuthData,charsmax(AuthData));
		
		if (Flags & FLAG_AUTHID)
		{
			if (equal(authid, AuthData))
			{
				index = i
				break
			}
		}
		else if (Flags & FLAG_IP)
		{
			new c = strlen(AuthData)
			
			// Поддержка префикса IP: запись с точкой на конце работает как маска подсети.
			if (AuthData[c - 1] == '.')		/* check if this is not a xxx.xxx. format */
			{
				if (equal(AuthData, ip, c))
				{
					index = i
					break
				}
			}									/* in other case an IP must just match */
			else if (equal(ip, AuthData))
			{
				index = i
				break
			}
		} 
		else 
		{
			if (Flags & FLAG_CASE_SENSITIVE)
			{
				if (Flags & FLAG_TAG)
				{
					if (contain(name, AuthData) != -1)
					{
						index = i
						g_CaseSensitiveName[id] = true
						break
					}
				}
				else if (equal(name, AuthData))
				{
					index = i
					g_CaseSensitiveName[id] = true
					break
				}
			}
			else
			{
				if (Flags & FLAG_TAG)
				{
					if (containi(name, AuthData) != -1)
					{
						index = i
						break
					}
				}
				else if (equali(name, AuthData))
				{
					index = i
					break
				}
			}
		}
	}

	if (index != -1)
	{
		Access=admins_lookup(index,AdminProp_Access);

		if (Flags & FLAG_NOPASS)
		{
			result |= 8
			new sflags[32]
			
			get_flags(Access, sflags, charsmax(sflags))
			set_user_flags(id, Access)
			
			log_amx("Login: ^"%s<%d><%s><>^" became an admin (account ^"%s^") (access ^"%s^") (address ^"%s^")", name, get_user_userid(id), authid, AuthData, sflags, ip)
		}
		else 
		{
		
			admins_lookup(index,AdminProp_Password,Password,charsmax(Password));

			if (equal(password, Password))
			{
				result |= 12
				set_user_flags(id, Access)
				
				new sflags[32]
				get_flags(Access, sflags, charsmax(sflags))
				
				log_amx("Login: ^"%s<%d><%s><>^" became an admin (account ^"%s^") (access ^"%s^") (address ^"%s^")", name, get_user_userid(id), authid, AuthData, sflags, ip)
			} 
			else 
			{
				result |= 1
				
				if (Flags & FLAG_KICK)
				{
					result |= 2
					log_amx("Login: ^"%s<%d><%s><>^" kicked due to invalid password (account ^"%s^") (address ^"%s^")", name, get_user_userid(id), authid, AuthData, ip)
				}
			}
		}
	}
	else if (get_pcvar_float(amx_mode) == 2.0)
	{
		result |= 2
	} 
	else 
	{
		new defaccess[32]
		
		get_pcvar_string(amx_default_access, defaccess, charsmax(defaccess))
		
		if (!strlen(defaccess))
		{
			copy(defaccess, charsmax(defaccess), "z")
		}
		
		new idefaccess = read_flags(defaccess)
		
		if (idefaccess)
		{
			result |= 8
			set_user_flags(id, idefaccess)
		}
	}
	
	return result
}

// Проверяет и назначает права конкретному игроку по текущим данным (ник/steamid/ip/пароль).
accessUser(id, name[] = "")
{
	remove_user_flags(id)
	
	new userip[32], userauthid[32], password[32], passfield[32], username[MAX_NAME_LENGTH]
	
	get_user_ip(id, userip, charsmax(userip), 1)
	get_user_authid(id, userauthid, charsmax(userauthid))
	
	if (name[0])
	{
		copy(username, charsmax(username), name)
	}
	else
	{
		get_user_name(id, username, charsmax(username))
	}
	
	get_pcvar_string(amx_password_field, passfield, charsmax(passfield))
	get_user_info(id, passfield, password, charsmax(password))
	
	new result = getAccess(id, username, userauthid, userip, password)
	
	if (result & 1)
	{
		engclient_print(id, engprint_console, "* %L", id, "INV_PAS")
	}
	
	if (result & 2)
	{
		server_cmd("kick #%d ^"%L^"", get_user_userid(id), id, "NO_ENTRY")
		return PLUGIN_HANDLED
	}
	
	if (result & 4)
	{
		engclient_print(id, engprint_console, "* %L", id, "PAS_ACC")
	}
	
	if (result & 8)
	{
		engclient_print(id, engprint_console, "* %L", id, "PRIV_SET")
	}
	
	return PLUGIN_CONTINUE
}

// Отслеживает смену ника и повторно валидирует админские права при необходимости.
public client_infochanged(id)
{
	if (!is_user_connected(id) || !get_pcvar_num(amx_mode))
	{
		return PLUGIN_CONTINUE
	}

	new newname[MAX_NAME_LENGTH], oldname[MAX_NAME_LENGTH]
	
	get_user_name(id, oldname, charsmax(oldname))
	get_user_info(id, "name", newname, charsmax(newname))

	if (g_CaseSensitiveName[id])
	{
		if (!equal(newname, oldname))
		{
			accessUser(id, newname)
		}
	}
	else
	{
		if (!equali(newname, oldname))
		{
			accessUser(id, newname)
		}
	}
	return PLUGIN_CONTINUE
}

// Вызывается после авторизации игрока и запускает проверку прав.
public client_authorized(id)
	return get_pcvar_num(amx_mode) ? accessUser(id) : PLUGIN_CONTINUE

// Обрабатывает вход игрока на сервер (в том числе listen-сервер) и при необходимости назначает права.
public client_putinserver(id)
{
	if (!is_dedicated_server() && id == 1)
		return get_pcvar_num(amx_mode) ? accessUser(id) : PLUGIN_CONTINUE
	
	return PLUGIN_CONTINUE
}
