#import "CGDGuidePrompts.h"

NSUInteger const CGDGuidePromptLimit = 6000;
static NSString *const CGDPromptPreference = @"CGDClassicalGuide.ModulePrompts";

NSArray *CGDPromptModuleIDs(void) {
    return @[@"translation", @"breakdown", @"background", @"performers", @"listening"];
}
NSString *CGDPromptModuleTitle(NSString *module) {
    return [@{@"translation": @"曲名翻译", @"breakdown": @"标题拆解", @"background": @"作品背景",
        @"performers": @"演奏者 / 乐团", @"listening": @"欣赏提示"} objectForKey:module];
}
NSString *CGDPromptModuleField(NSString *module) {
    return [@{@"translation": @"translated_title", @"breakdown": @"title_breakdown", @"background": @"background",
        @"performers": @"performer_info", @"listening": @"listening_tips"} objectForKey:module];
}
static NSString *CGDModulePromptForVersion(NSString *module, BOOL current) {
    NSString *specific = [@{
        @"translation": @"完整翻译当前曲名，保留作品类型、目录编号及数字（BWV、K./KV、Op. 等）、原有罗马数字乐章编号和调性。调性翻译后在括号中保留原始标记，例如 D Major。专有名称可保留原文，无法可靠翻译的词直接保留原文。只写曲名。",
        @"breakdown": @"解释标题中实际存在且能可靠解释的作品类型、目录编号、乐章、速度和表情术语；term 写原文术语，explanation 写目标语言解释。最多16项，每项解释1至2句。无法解释的术语直接略过，没有适用内容时返回空数组。",
        @"background": @"用易懂的语言简短介绍当前作品背景。只写较有把握的常识，未知的年代、创作缘由或录音版本直接略过。中文约150至300字，其他语言约80至150词；内容足够时可以更短，不凑字数。整段没有可靠内容时返回空字符串。",
        @"performers": @"阅读整个艺术家名单，区分作曲家、改编者、指挥、独奏者和乐团，不按名字顺序猜测身份。只介绍能可靠识别的演奏者、指挥或乐团，先用一两句介绍身份、主要乐器或艺术领域，再用一两句自然联系当前作品的体裁、乐章、声部关系或聆听重点，避免独立的人物小传。联系须有依据，可以从作品本身提出聆听建议；不要把一般艺术特点写成这次录音的实际听感，不编造合作经历、录音年代或演出事实。专辑标题出现的人名不能单独作为参与该曲录音的证据。身份筛选过程不要写进正文，尤其不要追加“某某不是演奏者”“某某并非演奏者”等排除说明。没有可靠的作品联系时保留简短人物事实；没有可靠介绍对象时返回空字符串。约3至4句，中文约100至200字，其他语言约60至110词，可更短。",
        @"listening": @"结合当前作品或乐章，给出容易跟随的聆听方向，例如旋律交接、声部层次、主题再现或节奏变化。最多5条，每条1至2句。不要把推测写成这次录音的确切特点。非古典作品只给适用提示，不硬套古典分析。没有适用内容时返回空数组。"
    } objectForKey:module];
    if (!specific) return nil;
    if (current && [module isEqual:@"background"]) specific = [specific stringByAppendingString:
        @"\n先准确辨认作品、选段或乐章以及改编关系。当前曲目是某一乐章时，重点介绍该乐章在作品中的作用；只需一句交代整部作品。标题包含编曲者时，区分原作与编配，不把改编者当作原作作者。避免与曲名翻译、人物小传重复，不编写戏剧化的创作故事。"];
    if (current && [module isEqual:@"performers"]) specific = [specific stringByAppendingString:
        @"\n针对同一作品的不同录音，介绍应对应本曲艺术家名单，不从相邻曲目或同一专辑的其他轨道借用演奏者。用名字明确对应角色；能够确认当前编制时，围绕该乐器或声部与本曲的联系展开。少用‘享誉世界’‘大师级’等赞美性套话。"];
    if (current && [module isEqual:@"listening"]) specific = [specific stringByAppendingString:
        @"\n优先写2至3条短而具体、边听边能做的观察：听哪个声部、关注什么变化、下次出现时比较什么。每条至少包含一个可听见的对象和一种观察动作。避免‘感受优美旋律’‘体会丰富情感’之类可用于任何曲目的套话。不要虚构时间戳、主题出现次数、曲式段落或当前录音的音色、速度；无法可靠识别作品细节时，从标题可支持的乐器、体裁或速度给出可行的观察。"];
    return [specific stringByAppendingString:@"\n\n只保留有把握的事实和有用内容。缺乏依据的内容直接省略，不把推测改成确定事实。不输出“不确定”“无法确认”“不代表”“不等同于”“不知道”“信息不足”等提示，不解释自己缺少什么资料，不在段末追加免责声明；此要求适用于所有目标语言。"];
}
NSString *CGDDefaultModulePrompt(NSString *module) { return CGDModulePromptForVersion(module, YES); }
NSDictionary *CGDGuidePromptsBefore050(NSDictionary *prompts) {
    NSMutableDictionary *candidate = [CGDNormalizeGuidePrompts(prompts) mutableCopy];
    for (NSString *module in CGDPromptModuleIDs()) {
        if ([[candidate objectForKey:module] isEqual:CGDDefaultModulePrompt(module)])
            [candidate setObject:CGDModulePromptForVersion(module, NO) forKey:module];
    }
    return [NSDictionary dictionaryWithDictionary:candidate];
}
static NSString *CGDValidPrompt(id value) {
    if (![value isKindOfClass:NSString.class] || [value length] > CGDGuidePromptLimit) return nil;
    NSString *text = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return text.length ? [NSString stringWithString:text] : nil;
}
NSDictionary *CGDNormalizeGuidePrompts(id prompts) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *module in CGDPromptModuleIDs()) {
        NSString *text = [prompts isKindOfClass:NSDictionary.class] ? CGDValidPrompt([prompts objectForKey:module]) : nil;
        [result setObject:text ?: CGDDefaultModulePrompt(module) forKey:module];
    }
    return [NSDictionary dictionaryWithDictionary:result];
}
NSDictionary *CGDLoadGuidePrompts(void) {
    return CGDNormalizeGuidePrompts([NSUserDefaults.standardUserDefaults objectForKey:CGDPromptPreference]);
}
NSString *CGDSaveModulePrompt(NSString *module, NSString *text) {
    if (![CGDPromptModuleIDs() containsObject:module]) return @"未找到此导赏模块。";
    NSString *valid = CGDValidPrompt(text);
    if (!valid) return @"提示词需包含 1–6000 个字符；可以点击“恢复默认”重新填写。";
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:CGDPromptPreference];
    NSMutableDictionary *updated = [NSMutableDictionary dictionary];
    // Persist only custom entries, so untouched defaults can improve on upgrade.
    for (NSString *key in CGDPromptModuleIDs()) {
        NSString *existing = [stored isKindOfClass:NSDictionary.class] ? CGDValidPrompt([stored objectForKey:key]) : nil;
        if (existing) [updated setObject:existing forKey:key];
    }
    if ([valid isEqual:CGDDefaultModulePrompt(module)]) [updated removeObjectForKey:module];
    else [updated setObject:valid forKey:module];
    [NSUserDefaults.standardUserDefaults setObject:updated forKey:CGDPromptPreference];
    return nil;
}
void CGDResetModulePrompt(NSString *module) {
    if ([CGDPromptModuleIDs() containsObject:module]) CGDSaveModulePrompt(module, CGDDefaultModulePrompt(module));
}
