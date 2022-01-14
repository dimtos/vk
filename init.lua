log		= require 'log'
yaml	= require 'yaml'
fiber	= require 'fiber'
json	= require 'json'

--
-- задача тестовая, очищаем БД при каждом запуске инстанса;
-- в ином случае отслеживали бы при создании наличие спейса,
-- соответствие формата и пр.
--
for _, x in box.space._vspace:pairs( 512, { iterator = 'GE' } ) do
	log.info('Dropping space `'.. x[3] ..'`')
	box.space[ x[1] ]:drop()
end

--
-- по-старинке прочитаем файл, а можно заюзать модуль fio из Tarantool-а
--
local lines = ''
for line in io.lines('schema.yaml') do lines = lines .. line end
local schema = yaml.decode(lines)

--
-- в нашем примере подзразумеваем, что схемой занимаются ответственные разрабы, и проверки не требуются
--
for space, opts in pairs(schema) do

	local reserved = {}

	for k, v in pairs(opts) do
		if k:match('^___') then -- если на тройное подчёркивание, наше зарезервированное слово
			reserved[k] = v
			opts[k] = nil
		end
	end

	log.info('Creating space `'.. space ..'`')
	local s = box.schema.space.create( space, opts )

	if reserved.___indexes then
		for idx, iopts in pairs(reserved.___indexes) do
			log.info('Creating index `'.. idx ..'`')
			s:create_index( idx, iopts )
		end
	end

end

--
-- загрузим классы именно в том порядке, в котором заданы; у нас только один
--
local preloads = dofile('preload.lua')

--
-- наш собственный глобальный основной объект
--
app =
{
	config = -- конфиг вынести в файл YAML
	{
		max_queries_per_second = 1,
		httpd = {},
	},
}

app.config.httpd.host, app.config.httpd.port = unpack(( __INSTANCE_SETTINGS__.host.httpd:split(':') )) -- представляется, что там логичнее хранить эти настройки

for _, x in ipairs(preloads) do
	local ok, res = pcall( require, x )
	local path = x:gsub( '%.', '/' ):split('/')
	local obj = app
	for i, cl in ipairs(path) do
		if i == #path then
			log.info('Loading class `'.. x ..'`')
			obj[cl] = require(x) -- выдаст ошибку, если криво указан путь
		else
			obj[cl] = {}
			obj = obj[cl]
		end
	end
end
