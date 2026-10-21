#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// AI 问答偏好键（com.lindo.metis.keyboard 域）。Settings 端写入权威域+共享快照，键盘
// 进程面板经 MTPrefsManager 快照读取。带引擎后缀的键按引擎标识拼接。
#define MTAIPrefEngine           @"aiEngine"
#define MTAIPrefKeyPrefix        @"aiKey_"
#define MTAIPrefModelsPrefix     @"aiModels_"
#define MTAIPrefSelectedPrefix   @"aiSelectedModel_"
#define MTAIPrefCustomEndpoint   @"aiCustomEndpoint"
#define MTAIPrefCustomName       @"aiCustomName"
#define MTAIPrefPersona          @"aiPersona"
#define MTAIPrefStream           @"aiStreamBOOL"
// 自定义引擎列表（array of dict：id/name/endpoint/key/models/selected）与人设
// 库（array of dict：id/name/content/role/enabled）。
#define MTAIPrefCustomEngines    @"aiCustomEngines"
#define MTAIPrefPersonas         @"aiPersonas"

// 一个 OpenAI 兼容引擎。请求统一走 {baseURL}/chat/completions，
// 模型抓取统一走 {baseURL}/models（含 Gemini 的 OpenAI 兼容端点）。
@interface MTAIEngineInfo : NSObject
@property (nonatomic, copy) NSString *identifier;    // qwen / deepseek / c<时间戳>（自定义）
@property (nonatomic, copy) NSString *displayName;   // 通义千问 / DeepSeek / ...
@property (nonatomic, copy) NSString *baseURL;       // 预设端点（custom 引擎为偏好里的端点）
@property (nonatomic, copy) NSString *defaultModels; // 默认模型列表（每行一个，兼容逗号分隔）
@property (nonatomic, copy) NSString *keysURL;       // 获取 API Key 的网页
@property (nonatomic, assign) BOOL custom;           // 自定义引擎（配置存 aiCustomEngines 列表）
@property (nonatomic, copy) NSString *overrideAPIKey; // 编辑页用未保存值抓模型时直填
@end

// 一次对话请求的句柄：面板的"停止"按钮据此取消流式任务。
@interface MTAIChatRequest : NSObject
- (void)cancel;
@end

@interface MTAIEngine : NSObject
+ (NSArray<MTAIEngineInfo *> *)allEngines;      // 内置预设
+ (NSArray<MTAIEngineInfo *> *)customEngines;   // 偏好里的自定义引擎
+ (MTAIEngineInfo *)currentEngine;
+ (MTAIEngineInfo *)engineForIdentifier:(NSString *)identifier;

// 配置读取：偏好值缺失时回退引擎预设（模型回退 defaultModels，选中模型回退首个）。
+ (NSString *)apiKeyForEngine:(MTAIEngineInfo *)engine;
+ (NSString *)endpointForEngine:(MTAIEngineInfo *)engine;
+ (NSArray<NSString *> *)modelsForEngine:(MTAIEngineInfo *)engine;
+ (NSString *)selectedModelForEngine:(MTAIEngineInfo *)engine;
+ (void)setSelectedModelForEngine:(MTAIEngineInfo *)engine model:(NSString *)model;

// 自定义引擎管理（aiCustomEngines 列表；新增返回生成的引擎 id）。
+ (NSString *)addCustomEngineWithName:(NSString *)name
                             endpoint:(NSString *)endpoint
                              apiKey:(NSString *)apiKey
                               models:(NSString *)models;
+ (void)updateCustomEngineWithID:(NSString *)engineID key:(NSString *)field value:(id)value;
+ (void)removeCustomEngineWithID:(NSString *)engineID; // 删除的是当前引擎时回退到首个内置

// 人设库。列表顺序即面板人设菜单顺序，第一项为默认人设（设置页长按拖动
// 排序决定）；旧的单条 aiPersona 文本首次读取时迁入 AI问答助手。
+ (NSArray<NSDictionary *> *)personas;
+ (void)setPersonas:(NSArray<NSDictionary *> *)personas;
+ (NSDictionary *)personaForID:(NSString *)personaID;
+ (NSDictionary *)defaultPersona; // 列表第一项；列表为空时返回 nil

// 面板行为偏好。
+ (BOOL)streamEnabled;
+ (NSString *)personaPrompt; // 兼容旧单条人设读取（现仅迁移前有效）

// 发送一轮对话。messages 为请求形状：{role, content}，content 是字符串或
// OpenAI 视觉 parts 数组。stream 时 onDelta 增量回调，onDone 在结束/失败时
// 恰好调用一次（fullText 为累计全文，失败时为已收到的部分）。返回的句柄
// 可 cancel（onDone 会以 code=-999 结束）。
+ (MTAIChatRequest *)sendChatWithMessages:(NSArray<NSDictionary *> *)messages
                      engine:(MTAIEngineInfo *)engine
                       onDelta:(void (^)(NSString *piece))onDelta
                      onDone:(void (^)(NSString *fullText, NSError *error))onDone;

// 会话级模型覆盖：model 非空时本次请求用它，不读写 aiSelectedModel_ 全局键，
// 因此 AI 动作绑定的模型不会改掉面板里用户当前的模型选择。model 为空等价于
// 上面的默认入口（selectedModelForEngine，缺省回退列表第一项）。
+ (MTAIChatRequest *)sendChatWithMessages:(NSArray<NSDictionary *> *)messages
                      engine:(MTAIEngineInfo *)engine
                       model:(NSString *)model
                     onDelta:(void (^)(NSString *piece))onDelta
                      onDone:(void (^)(NSString *fullText, NSError *error))onDone;

// 拉取引擎可用模型列表，按接口地址自适应厂商（请求路径 + token 鉴权头）：
// OpenAI 兼容（Bearer）/ Gemini 原生（x-goog-api-key，剔除不支持
// generateContent 的模型）/ Anthropic（x-api-key + anthropic-version）/
// Ollama（/api/tags，无鉴权）；响应形态宽松解析（data[]/models[]/裸数组）。
+ (void)fetchModelsForEngine:(MTAIEngineInfo *)engine
                  completion:(void (^)(NSArray<NSString *> *models, NSError *error))completion;

+ (BOOL)supportsBalanceForEngine:(MTAIEngineInfo *)engine;
// Main-thread completion. Throttled: at most one request per 30s per engine
// configuration (identifier + endpoint + key); triggers inside the window
// reuse the last result (success text or failure reason) instead of
// re-querying, and concurrent triggers for the same configuration share one
// in-flight request. Cache is in-memory only; does not persist account data
// or API keys.
+ (void)fetchBalanceForEngine:(MTAIEngineInfo *)engine
                 completion:(void (^)(NSString *balance, NSError *error))completion;
@end
