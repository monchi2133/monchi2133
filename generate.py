"""
女子心理攻略ちゃんねら — YouTubeショート動画コンテンツ自動生成スクリプト

1回の実行で10テーマ分の動画コンテンツを生成し、outputs/ フォルダにJSONで保存します。
テーマ形式: 「女子の意外な〇〇3選」
"""

import anthropic
import json
import os
from datetime import datetime

SYSTEM_PROMPT = """あなたは女性心理・行動心理学の専門家であり、
YouTubeショート動画「女子心理攻略ちゃんねら」のコンテンツ企画者です。

コンテンツの原則:
- 「女子の意外な〇〇3選」という形式でテーマを設定する
- 回答は必ず心理学的根拠（認知バイアス・社会心理学・進化心理学など）に基づいていること
- 「え、本当に？」と思わせる反直感的な内容にする
- 具体的で実体験に近い例を盛り込む
- 視聴者が「これ、あるある！」または「知らなかった！」と感じる内容にする
- 科学的に信頼性のある研究や理論を参照する（具体的な研究名や心理学用語を含める）"""

USER_PROMPT = """以下のJSON形式で、YouTubeショート動画のコンテンツを10テーマ分生成してください。
各テーマは独立した動画1本分です。

出力形式（JSONのみ、説明文なし）:
{
  "themes": [
    {
      "title": "女子の意外な〇〇3選",
      "description": "このテーマの概要（1〜2文）",
      "psychological_basis": "参照する心理学理論・研究名",
      "items": [
        {
          "number": 1,
          "point": "ポイントのタイトル（短く印象的に）",
          "explanation": "詳しい説明（視聴者が「なるほど！」と思える内容、50〜80文字）",
          "example": "具体的なシーン・例（実体験に近いもの）",
          "psychology_note": "心理学的根拠の補足"
        },
        {
          "number": 2,
          "point": "ポイントのタイトル",
          "explanation": "詳しい説明",
          "example": "具体的なシーン・例",
          "psychology_note": "心理学的根拠の補足"
        },
        {
          "number": 3,
          "point": "ポイントのタイトル",
          "explanation": "詳しい説明",
          "example": "具体的なシーン・例",
          "psychology_note": "心理学的根拠の補足"
        }
      ],
      "hook": "動画冒頭の掴みセリフ（視聴者を引き込む1文）",
      "cta": "動画末尾のCTA（フォロー・コメント誘導）"
    }
  ]
}

テーマのバリエーション例（これに限らず多様なテーマで）:
- 女子が「好き」なのに意地悪な行動をとる理由3選
- 女子がLINEを既読スルーする本当の理由3選
- 女子が「どこでもいい」と言う時の本音3選
- 女子が褒められると逆に不安になる状況3選
- 女子が嫉妬を隠す時に使う行動3選

10テーマ全て異なるテーマで、どれも反直感的で心理学的根拠のある内容にしてください。
JSONのみ出力してください。"""


def generate_content() -> dict:
    client = anthropic.Anthropic()

    print("コンテンツ生成中... (Claude claude-opus-4-6 使用)")

    with client.messages.stream(
        model="claude-opus-4-6",
        max_tokens=8000,
        thinking={"type": "adaptive"},
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": USER_PROMPT}],
    ) as stream:
        for event in stream:
            if (
                event.type == "content_block_start"
                and hasattr(event, "content_block")
                and event.content_block.type == "thinking"
            ):
                print("  [思考中...]")

        final_message = stream.get_final_message()

    raw_text = ""
    for block in final_message.content:
        if block.type == "text":
            raw_text = block.text
            break

    # JSONブロックを抽出（```json ... ``` 形式にも対応）
    text = raw_text.strip()
    if text.startswith("```"):
        lines = text.split("\n")
        start = 1 if lines[0].startswith("```") else 0
        end = len(lines) - 1 if lines[-1] == "```" else len(lines)
        text = "\n".join(lines[start:end])

    data = json.loads(text)
    data["generated_at"] = datetime.now().isoformat()
    data["model"] = "claude-opus-4-6"
    data["theme_count"] = len(data.get("themes", []))

    return data


def save_output(data: dict) -> str:
    os.makedirs("outputs", exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filepath = f"outputs/themes_{timestamp}.json"

    with open(filepath, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    return filepath


def main():
    print("=" * 60)
    print("女子心理攻略ちゃんねら — コンテンツ自動生成")
    print("=" * 60)

    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("エラー: ANTHROPIC_API_KEY 環境変数が設定されていません。")
        print("  export ANTHROPIC_API_KEY='your-api-key'")
        return

    try:
        data = generate_content()
        filepath = save_output(data)

        print(f"\n✓ {data['theme_count']} テーマ分のコンテンツを生成しました")
        print(f"✓ 保存先: {filepath}")
        print("\n生成されたテーマ一覧:")
        for i, theme in enumerate(data.get("themes", []), 1):
            print(f"  {i:2}. {theme['title']}")
        print("\n完了！")

    except json.JSONDecodeError as e:
        print(f"エラー: JSONパースに失敗しました: {e}")
        raise
    except anthropic.APIError as e:
        print(f"エラー: API呼び出しに失敗しました: {e}")
        raise


if __name__ == "__main__":
    main()
