"""
女子心理攻略ちゃんねら — エージェントチーム収益化システム

【5万円達成戦略】
- YouTube Shortsは1,000登録者 + 1,000万再生でパートナー収益化
- 並行してnote/Brain有料記事(1記事500〜1,000円)で即収益化
- アフィリエイト誘導コンテンツで物販収益

【エージェント構成】
1. OrchestratorAgent    - 全体指揮・KPI管理
2. TrendResearchAgent   - トレンドテーマ・競合分析
3. ScriptWriterAgent    - 動画スクリプト一括生成
4. SeoOptimizerAgent    - タイトル/説明/ハッシュタグ最適化
5. QualityReviewAgent   - エンゲージメント予測・品質チェック
6. MonetizationAgent    - 収益化戦略・note記事化・アフィリエイト設計
"""

import anthropic
import json
import os
from datetime import datetime
from typing import Any


client = anthropic.Anthropic()
MODEL = "claude-opus-4-6"


# ─────────────────────────────────────────────
# ユーティリティ
# ─────────────────────────────────────────────

def call_agent(agent_name: str, system: str, user_message: str, max_tokens: int = 4000) -> str:
    """エージェントを呼び出し、テキスト応答を返す"""
    print(f"\n  [{agent_name}] 稼働中...")
    response = client.messages.create(
        model=MODEL,
        max_tokens=max_tokens,
        system=system,
        messages=[{"role": "user", "content": user_message}],
    )
    return response.content[0].text


def parse_json_response(text: str) -> Any:
    """JSONレスポンスを安全にパース"""
    text = text.strip()
    if text.startswith("```"):
        lines = text.split("\n")
        start = 1
        end = len(lines) - 1 if lines[-1].strip() == "```" else len(lines)
        text = "\n".join(lines[start:end])
    return json.loads(text)


# ─────────────────────────────────────────────
# Agent 1: TrendResearchAgent
# ─────────────────────────────────────────────

TREND_SYSTEM = """あなたはYouTube Shortsのトレンド分析専門家です。
女性心理・恋愛・人間関係ジャンルの「バズるテーマ」を選定します。

選定基準:
- 検索ボリュームが高そうなキーワードを含む
- 感情的反応(共感・驚き・怒り)を引き出す
- 10〜30秒で完結する構成に向いている
- 収益化コンテンツ(恋愛/美容/自己啓発商品)と連携しやすい"""

def trend_research_agent(previous_themes: list[str] = []) -> dict:
    """トレンドテーマを調査・提案する"""
    avoid = "\n".join(f"- {t}" for t in previous_themes) if previous_themes else "なし"
    prompt = f"""以下のJSONで、YouTubeショート向け高バズテーマを15個提案してください。

避けるテーマ（重複NG）:
{avoid}

出力形式（JSONのみ）:
{{
  "themes": [
    {{
      "title": "女子の意外な〇〇3選",
      "target_emotion": "共感|驚き|怒り|笑い",
      "monetization_type": "アフィリエイト商品カテゴリ or note記事化 or 広告収益",
      "estimated_virality": 1〜10の整数,
      "keywords": ["キーワード1", "キーワード2", "キーワード3"]
    }}
  ]
}}"""
    result = call_agent("TrendResearchAgent", TREND_SYSTEM, prompt, max_tokens=3000)
    return parse_json_response(result)


# ─────────────────────────────────────────────
# Agent 2: ScriptWriterAgent
# ─────────────────────────────────────────────

SCRIPT_SYSTEM = """あなたはYouTube Shortsのプロスクリプターです。
「女子心理攻略ちゃんねら」の台本を書きます。

台本の原則:
- 最初の3秒で視聴者を掴む「衝撃フック」を入れる
- 各ポイントは10〜15秒で読めるテンポにする
- 心理学用語を1つ入れて「専門性」を演出する
- 最後にコメント・フォローを促すCTAを入れる
- 合計尺: 45〜60秒（字数250〜350文字）"""

def script_writer_agent(themes: list[dict]) -> list[dict]:
    """テーマリストから台本を一括生成する"""
    theme_list = "\n".join(
        f"{i+1}. {t['title']} (感情:{t['target_emotion']}, 収益:{t['monetization_type']})"
        for i, t in enumerate(themes[:5])  # 上位5テーマ
    )
    prompt = f"""以下5テーマ分の完全台本をJSONで生成してください。

テーマ:
{theme_list}

出力形式（JSONのみ）:
{{
  "scripts": [
    {{
      "title": "テーマタイトル",
      "hook": "冒頭3秒の衝撃セリフ",
      "script_body": "本編台本（ポイント1〜3を含む完全台本）",
      "psychology_keyword": "使用した心理学用語",
      "cta": "CTAセリフ",
      "estimated_duration_sec": 推定秒数（整数）,
      "char_count": 文字数（整数）
    }}
  ]
}}"""
    result = call_agent("ScriptWriterAgent", SCRIPT_SYSTEM, prompt, max_tokens=6000)
    return parse_json_response(result)["scripts"]


# ─────────────────────────────────────────────
# Agent 3: SeoOptimizerAgent
# ─────────────────────────────────────────────

SEO_SYSTEM = """あなたはYouTube SEOのエキスパートです。
Shortsの表示回数を最大化するタイトル・説明文・ハッシュタグを設計します。

最適化ポイント:
- タイトルは30文字以内、感情語・数字・「女子」「心理」を含める
- 説明文は最初の100文字が重要（検索スニペットに表示される）
- ハッシュタグは #Shorts を必ず含め、合計5〜8個
- サジェストキーワードを自然に埋め込む"""

def seo_optimizer_agent(scripts: list[dict]) -> list[dict]:
    """台本リストにSEO情報を付与する"""
    titles = "\n".join(f"{i+1}. {s['title']}" for i, s in enumerate(scripts))
    prompt = f"""以下{len(scripts)}本の動画にSEO情報を付与してJSONで返してください。

動画タイトル:
{titles}

出力形式（JSONのみ）:
{{
  "seo_data": [
    {{
      "original_title": "元のテーマタイトル",
      "optimized_title": "SEO最適化済みタイトル（30文字以内）",
      "description": "YouTube説明文（150文字、キーワード自然埋め込み）",
      "hashtags": ["#Shorts", "#女子心理", "その他5個"],
      "thumbnail_text": "サムネイル文字（10文字以内、インパクト重視）",
      "seo_score": 1〜10の整数
    }}
  ]
}}"""
    result = call_agent("SeoOptimizerAgent", SEO_SYSTEM, prompt, max_tokens=3000)
    return parse_json_response(result)["seo_data"]


# ─────────────────────────────────────────────
# Agent 4: QualityReviewAgent
# ─────────────────────────────────────────────

REVIEW_SYSTEM = """あなたはYouTube Shortsのバイラルコンテンツ審査官です。
エンゲージメント率・保持率・シェア率を予測し、改善点を指摘します。

審査基準:
- フック強度: 最初3秒で離脱を防げるか
- 情報密度: 45〜60秒に価値を詰め込めているか
- 感情起伏: 驚き→共感→行動の流れがあるか
- CTA明確性: コメント・フォロー誘導が自然か"""

def quality_review_agent(scripts: list[dict], seo_data: list[dict]) -> dict:
    """品質レビューと改善提案を行う"""
    combined = []
    for s, seo in zip(scripts, seo_data):
        combined.append({
            "title": seo.get("optimized_title", s["title"]),
            "hook": s["hook"],
            "cta": s["cta"],
            "duration": s.get("estimated_duration_sec", "不明"),
            "seo_score": seo.get("seo_score", 0),
        })

    prompt = f"""以下{len(combined)}本の動画を審査し、JSONで返してください。

動画データ:
{json.dumps(combined, ensure_ascii=False, indent=2)}

出力形式（JSONのみ）:
{{
  "reviews": [
    {{
      "title": "動画タイトル",
      "hook_score": 1〜10,
      "engagement_prediction": "高|中|低",
      "priority": "最優先投稿|優先投稿|通常投稿",
      "improvement": "改善提案（1文）"
    }}
  ],
  "overall_summary": "全体評価コメント（2〜3文）"
}}"""
    result = call_agent("QualityReviewAgent", REVIEW_SYSTEM, prompt, max_tokens=2000)
    return parse_json_response(result)


# ─────────────────────────────────────────────
# Agent 5: MonetizationAgent
# ─────────────────────────────────────────────

MONETIZATION_SYSTEM = """あなたはコンテンツ収益化のプロです。
YouTubeチャンネルを最短で5万円の収益に到達させる戦略を設計します。

収益化ルート:
1. YouTube Shortsパートナープログラム（1,000登録者 + 1,000万再生）
2. note有料記事（1記事500〜1,500円 × 毎月10本）
3. アフィリエイト（恋愛・心理学書籍・マッチングアプリ）
4. ファンボックス・メンバーシップ（月500円 × 100人）
5. コンテンツ販売（台本パック・テンプレート販売）"""

def monetization_agent(themes: list[dict], review: dict) -> dict:
    """収益化戦略と実行計画を立案する"""
    top_themes = [t["title"] for t in themes[:5]]
    summary = review.get("overall_summary", "")

    prompt = f"""以下の情報をもとに「5万円達成」の具体的収益化プランをJSONで返してください。

生成済みテーマ（上位5件）: {top_themes}
品質評価: {summary}

出力形式（JSONのみ）:
{{
  "target_revenue_jpy": 50000,
  "timeline_weeks": 達成予想週数（整数）,
  "revenue_breakdown": [
    {{
      "source": "収益源名",
      "monthly_jpy": 月収見込み（整数）,
      "required_action": "必要なアクション",
      "difficulty": "易|中|難"
    }}
  ],
  "weekly_content_plan": {{
    "shorts_per_week": 週投稿本数（整数）,
    "note_articles_per_week": 週note記事数（整数）,
    "best_posting_times": ["投稿推奨時間帯"],
    "growth_milestones": [
      {{"week": 週数, "goal": "マイルストーン目標"}}
    ]
  }},
  "immediate_actions": [
    "今すぐやること1",
    "今すぐやること2",
    "今すぐやること3"
  ],
  "note_article_ideas": [
    {{
      "title": "有料記事タイトル",
      "price_jpy": 価格（整数）,
      "content_summary": "記事概要（1文）"
    }}
  ]
}}"""
    result = call_agent("MonetizationAgent", MONETIZATION_SYSTEM, prompt, max_tokens=3000)
    return parse_json_response(result)


# ─────────────────────────────────────────────
# Orchestrator: 全エージェントを指揮する
# ─────────────────────────────────────────────

def orchestrator():
    """オーケストレーターエージェント — 5万円稼ぐまでの全工程を指揮"""

    print("=" * 65)
    print("  女子心理攻略ちゃんねら — エージェントチーム起動")
    print("  🎯 目標: 5万円収益達成プラン + 即投稿コンテンツ生成")
    print("=" * 65)

    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("\nエラー: ANTHROPIC_API_KEY が設定されていません。")
        print("  export ANTHROPIC_API_KEY='your-api-key'")
        return

    # ── Step 1: トレンド調査 ──────────────────────────────
    print("\n[Step 1/5] TrendResearchAgent — バズテーマ調査中...")
    trend_data = trend_research_agent()
    themes = trend_data["themes"]
    # バイラリティスコアでソート
    themes.sort(key=lambda x: x.get("estimated_virality", 0), reverse=True)
    print(f"  → {len(themes)} テーマ候補を取得")

    # ── Step 2: 台本生成 ──────────────────────────────────
    print("\n[Step 2/5] ScriptWriterAgent — 台本生成中...")
    scripts = script_writer_agent(themes)
    print(f"  → {len(scripts)} 本分の台本を生成")

    # ── Step 3: SEO最適化 ─────────────────────────────────
    print("\n[Step 3/5] SeoOptimizerAgent — SEO最適化中...")
    seo_data = seo_optimizer_agent(scripts)
    print(f"  → {len(seo_data)} 本分のSEO情報を生成")

    # ── Step 4: 品質レビュー ──────────────────────────────
    print("\n[Step 4/5] QualityReviewAgent — 品質審査中...")
    review = quality_review_agent(scripts, seo_data)
    print(f"  → 審査完了: {review.get('overall_summary', '')[:50]}...")

    # ── Step 5: 収益化戦略 ────────────────────────────────
    print("\n[Step 5/5] MonetizationAgent — 5万円達成プラン策定中...")
    monetization = monetization_agent(themes, review)
    print(f"  → 達成予想: {monetization.get('timeline_weeks', '?')}週間")

    # ── 結果を統合して保存 ────────────────────────────────
    output = {
        "generated_at": datetime.now().isoformat(),
        "model": MODEL,
        "target_revenue_jpy": 50000,
        "trend_themes": themes,
        "scripts": scripts,
        "seo_data": seo_data,
        "quality_review": review,
        "monetization_plan": monetization,
    }

    os.makedirs("outputs", exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filepath = f"outputs/agent_team_{timestamp}.json"
    with open(filepath, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    # ── サマリーレポート表示 ──────────────────────────────
    print("\n" + "=" * 65)
    print("  エージェントチーム — 実行完了レポート")
    print("=" * 65)

    print(f"\n📁 出力ファイル: {filepath}")

    print("\n🎬 即投稿コンテンツ (品質レビュー上位):")
    reviews = review.get("reviews", [])
    for r in reviews:
        priority_icon = "🔥" if r.get("priority") == "最優先投稿" else "⭐"
        print(f"  {priority_icon} [{r.get('priority','?')}] {r.get('title','')}")
        print(f"      フック:{r.get('hook_score','?')}/10 | 予測:{r.get('engagement_prediction','?')}")

    print("\n💰 5万円達成ロードマップ:")
    mp = monetization
    print(f"  達成予想: {mp.get('timeline_weeks','?')}週間")
    print(f"  週間投稿数: Shorts {mp.get('weekly_content_plan',{}).get('shorts_per_week','?')}本")
    for rb in mp.get("revenue_breakdown", []):
        print(f"  • {rb['source']}: 月{rb['monthly_jpy']:,}円 [{rb['difficulty']}] → {rb['required_action']}")

    print("\n🚀 今すぐやること:")
    for i, action in enumerate(mp.get("immediate_actions", []), 1):
        print(f"  {i}. {action}")

    print("\n📝 note有料記事プラン:")
    for article in mp.get("note_article_ideas", []):
        print(f"  • {article['title']} — {article['price_jpy']:,}円")

    print("\n✅ エージェントチーム完了！")
    print("=" * 65)

    return output


if __name__ == "__main__":
    orchestrator()
