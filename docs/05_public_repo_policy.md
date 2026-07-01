# 05_public_repo_policy

## 基本方針

このリポジトリは public repository として扱う。公開してよいものと公開してはいけないものを明確に分ける。

## 公開してよいもの

- Docker Compose の検証環境
- MediaMTX の example 設定
- 検証手順
- 再現可能なテストコマンド
- 匿名化した観察結果
- public documentation への参照

## 公開しないもの

- 実カメラ URL
- 実ユーザー名・パスワード
- API token / secret / private key
- 自宅・社内・クラウド環境の実 IP / host 名
- TURN / STUN の実認証情報
- 録画ファイル、キャプチャ画像、個人環境ログ
- 会社や顧客の構成情報

## 設定ファイル運用

- commit する: `*.example.yml`, `.env.example`
- commit しない: `.env`, `*.local.yml`, `docker-compose.override.yml`

## PR 確認観点

- 秘密情報が含まれていないか
- 実環境を推測できる情報が含まれていないか
- 録画・ログ・画像が混ざっていないか
- README の手順だけで再現できるか
